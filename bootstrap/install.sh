#!/usr/bin/env bash

#
# BS installer (Linux)
# Установщик BS (Linux)
#
# Режимы / Modes:
#   1) System install (нужен sudo/root) / Системная установка (нужен sudo/root):
#        sudo ./install.sh
#        sudo ./install.sh install
#
#   2) Local install (без sudo) в ~/.local / Локальная установка (без sudo) в ~/.local:
#        ./install.sh --local
#        ./install.sh --local install
#
# Удаление / Uninstall:
#   sudo ./install.sh uninstall
#   ./install.sh --local uninstall
#
# PATH helper / Помощник PATH:
# ./install.sh --local --path # печатает, что добавить в shell rc / печатает, что добавить
# в shell rc
# ./install.sh --local --update-path # добавляет в ~/.bashrc (с подтверждением) /
# добавляет в ~/.bashrc (с подтверждением)
#
# Переопределения (опционально)
#   PREFIX=... BIN_DIR=... LIB_DIR=...
#

# Безопасные настройки / Safe settings:
#   -e: выход при ошибке любой команды / exit on error of any command
#   -u: ошибка при использовании неопределенных переменных / error on use of undefined
# variables
#   -o pipefail: ошибка пайплайна если любая команда пайплайна упала / pipeline error if any
# pipeline command failed
set -euo pipefail

# Проверка, что скрипт запускается в поддерживаемой оболочке
check_shell_environment() {
    local shell_name
    
    # Определяем имя текущей оболочки
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        shell_name="zsh"
    elif [[ -n "${BASH_VERSION:-}" ]]; then
        shell_name="bash"
    elif [[ "$0" == *"bash"* ]]; then
        shell_name="bash"
    elif [[ "$0" == *"zsh"* ]]; then
        shell_name="zsh"
    elif [[ -n "${KSH_VERSION:-}" ]]; then
        shell_name="ksh"
    else
        shell_name="${0##*/}"  # последний компонент из $0
    fi

    # Проверяем, поддерживаемая ли это оболочка
    case "$shell_name" in
        bash|zsh|ksh|sh)
            return 0
            ;;
        *)
            printf "ERROR: Unsupported shell: %s\n" "$shell_name" >&2
            printf "This script requires bash, zsh, ksh, or sh to run.\n" >&2
            exit 1
            ;;
    esac
}

# Проверяем окружение оболочки перед продолжением
check_shell_environment

# Функция показа справки
# Function to show help
usage() {
	cat <<'HELP'
BS installer

Usage:
  ./install.sh [--local] [install|uninstall] [--path|--update-path]
  sudo ./install.sh [install|uninstall]

Examples:
  sudo ./install.sh
  sudo ./install.sh install
  sudo ./install.sh uninstall

  ./install.sh --local
  ./install.sh --local install
  ./install.sh --local uninstall

  ./install.sh --local --path
  ./install.sh --local --update-path
HELP
}

# Функция подтверждения действия
confirm() {
	local prompt="$1"
	local ans

	read -r -p "${prompt} [y/N]: " ans
	# Возвращает 0 (true) только если ответ y или Y
	[[ "${ans}" == "y" || "${ans}" == "Y" ]]
}

# Парсинг аргументов
MODE="system"        # system|local - режим установки
ACTION="install"     # install|uninstall - действие
FLAG_PATH="0"        # 0|1 - флаг печати PATH сниппета
FLAG_UPDATE_PATH="0" # 0|1 - флаг обновления ~/.bashrc

while [[ $# -gt 0 ]]; do
	case "$1" in
	--local)
		MODE="local"
		shift
		;;
	--path)
		FLAG_PATH="1"
		shift
		;;
	--update-path)
		FLAG_UPDATE_PATH="1"
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	install | uninstall | remove)
		ACTION="$1"
		shift
		;;
	*)
		printf "ERROR: %s\n" "Неизвестный аргумент: $1 (см. --help)" >&2
		exit 1
		;;
	esac
done

# Синоним для команды remove
if [[ "${ACTION}" == "remove" ]]; then
	ACTION="uninstall"
fi

# Определение абсолютного пути.
# Корневой директории вызова ./install т.е. исходников
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="${SCRIPT_DIR}"

# Определение целевых директорий
# Выбираем PREFIX в зависимости от режима
if [[ "${MODE}" == "local" ]]; then
	# Для локальной установки: ~/.local
	# ${PREFIX:="$HOME/.local"}: если PREFIX не задан, используем ~/.local
	: "${PREFIX:="$HOME/.local"}"
else
	# Для системной установки: /usr/local
	: "${PREFIX:=/usr/local}"
fi

# Определение BIN_DIR и LIB_DIR с умолчаниями:
# Синтаксис ${VAR:=default} проверяет, установлена ли переменная VAR.
# Если нет (или пустая), присваивает ей значение default.
# : перед кавычками - это no-op команда, которая только выполняет подстановку.
: "${BIN_DIR:="${PREFIX}/bin"}" # Если BIN_DIR не задан, используем ${PREFIX}/bin
: "${LIB_DIR:="${PREFIX}/lib"}" # Если LIB_DIR не задан, используем ${PREFIX}/lib

# Финальные пути установки
TARGET_LIB="${LIB_DIR}/BS" # Директория для библиотек BS
TARGET_BIN="${BIN_DIR}/BS" # Исполняемый файл

# Функция проверки, установлена ли система
is_already_installed() {
	if [[ -d "${TARGET_LIB}" && -f "${TARGET_BIN}" ]]; then
		return 0  # Уже установлена / Already installed
	else
		return 1  # Не установлена / Not installed yet
	fi
}

# Функция для генерации сниппета PATH для добавления в shell rc файлы
path_snippet() {
	cat <<'SNIP'
# BS (local) - add to PATH
export PATH="$HOME/.local/bin:$PATH"
SNIP
}

# Печать подсказки по настройке PATH
print_path_hint() {
	printf "Чтобы работало: #!/usr/bin/env BS\n"
	printf "Добавь ~/.local/bin в PATH. Например, в ~/.bashrc:\n"
	printf "\n"
	path_snippet
	printf "\n"
}

# Функция добавления PATH в ~/.bashrc
update_path_bashrc() {
	local bashrc="${HOME}/.bashrc"
	local line="export PATH=\"\$HOME/.local/bin:\$PATH\""

	# Создаем файл если не существует
	[[ -f "${bashrc}" ]] || touch "${bashrc}"

	# Проверяем, не добавлена ли уже строка
	if grep -Fqx "${line}" "${bashrc}"; then
		printf "PATH уже настроен в %s\n" "${bashrc}"
		return 0
	fi

	# Запрашиваем подтверждение
	if confirm "Добавить PATH в ${bashrc}?"; then
		# Добавляем строку в конец файла
		printf "\n%s\n" "${line}" >>"${bashrc}"
		printf "Добавлено. Применить: source ~/.bashrc\n"
	else
		printf "Пропущено.\n"
	fi
}

# Функция установки
do_install() {
	# Проверка прав для системной установки
	if [[ "${MODE}" == "system" ]]; then
		# ${EUID:-$(id -u)}: использует EUID если определена, иначе получает через id -u
		if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
			printf "ERROR: %s\n" "Нужны права root. Запусти: sudo ./install.sh" >&2
			exit 1
		fi
	fi

	# Проверяем, установлена ли система уже
	if is_already_installed; then
		printf "Предупреждение: BS уже установлена в %s\n" "${TARGET_LIB}"
		printf "Удалите сначала старую версию командой: ./install.sh uninstall\n"
		printf "Или используйте переопределения: PREFIX=... BIN_DIR=... LIB_DIR=...\n"
		exit 1
	fi

	printf "Установка BS (%s)\n" "${MODE}"
	printf "  SOURCE_ROOT: %s\n" "${SOURCE_ROOT}"
	printf "  PREFIX:      %s\n" "${PREFIX}"
	printf "  TARGET_LIB:  %s\n" "${TARGET_LIB}"
	printf "  TARGET_BIN:  %s\n" "${TARGET_BIN}"

	# Создаем целевые директории если их нет
	mkdir -p "${BIN_DIR}"
	mkdir -p "${LIB_DIR}"

	# Очищаем старую установку
	rm -rf "${TARGET_LIB}"
	mkdir -p "${TARGET_LIB}"

	# Копируем файлы BS
	cp -a "${SOURCE_ROOT}/bootstrap" "${TARGET_LIB}/"
	cp -a "${SOURCE_ROOT}/core" "${TARGET_LIB}/"
	cp -a "${SOURCE_ROOT}/BS" "${TARGET_LIB}/"
	cp -a "${SOURCE_ROOT}/bin" "${TARGET_LIB}/"
	cp -a "${SOURCE_ROOT}/lib" "${TARGET_LIB}/"

	# Создаем wrapper-скрипт
	cat >"${TARGET_BIN}" <<WRAP
#!/usr/bin/env bs
export BOSA_ROOT="${TARGET_LIB}"
exec "${TARGET_LIB}/bin/BS" "\$@"
WRAP

	chmod 0755 "${TARGET_BIN}"

	printf "Готово.\n"

	# Для локальной установки показываем подсказку по PATH
	if [[ "${MODE}" == "local" ]]; then
		print_path_hint
	fi
}

# Функция удаления
do_uninstall() {
	# Проверка прав для системного удаления
	if [[ "${MODE}" == "system" ]]; then
		# ${EUID:-$(id -u)}: использует EUID если определена, иначе получает через id -u
		if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
			printf "ERROR: %s\n" "Нужны права root. Запусти: sudo ./install.sh" >&2
			exit 1
		fi
	fi

	printf "Удаление BS (%s)\n" "${MODE}"
	printf "  TARGET_BIN: %s\n" "${TARGET_BIN}"
	printf "  TARGET_LIB: %s\n" "${TARGET_LIB}"

	# Удаляем исполняемый файл
	if [[ -f "${TARGET_BIN}" ]]; then
		rm -f "${TARGET_BIN}"
		printf "Удален: %s\n" "${TARGET_BIN}"
	else
		printf "Нет файла: %s\n" "${TARGET_BIN}"
	fi

	# Удаляем директорию с библиотеками
	if [[ -d "${TARGET_LIB}" ]]; then
		rm -rf "${TARGET_LIB}"
		printf "Удален: %s\n" "${TARGET_LIB}"
	else
		printf "Нет каталога: %s\n" "${TARGET_LIB}"
	fi

	printf "Готово.\n"
}

# Обработка флагов PATH (только для локального режима)
if [[ "${MODE}" == "local" && "${FLAG_PATH}" == "1" ]]; then
	print_path_hint
	exit 0
fi

if [[ "${MODE}" == "local" && "${FLAG_UPDATE_PATH}" == "1" ]]; then
	update_path_bashrc
	exit 0
fi

# Выполнение основного действия
case "${ACTION}" in
install)
	do_install
	;;
uninstall)
	do_uninstall
	;;
*)
	printf "ERROR: %s\n" "Неизвестное действие: ${ACTION}" >&2
	exit 1
	;;
esac
