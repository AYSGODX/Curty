#!/bin/bash
# Собирает Curty из исходников и устанавливает в «Программы».
# Повторный запуск обновляет приложение; данные при этом не теряются —
# заметки, сниппеты и полка живут в контейнере, привязанном к dev.curty.app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Curty.app"
BUILT_APP="$ROOT/.build/Products/$APP_NAME"

fail() {
    echo "$1" >&2
    exit 1
}

# --- Проверки окружения -----------------------------------------------------

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MACOS_MAJOR" -lt 15 ]; then
    fail "Curty требует macOS 15 или новее, у вас $(sw_vers -productVersion)."
fi

if ! command -v swift >/dev/null 2>&1; then
    fail "Не найден Swift. Установите инструменты разработчика и повторите:

    xcode-select --install

Это примерно полтора гигабайта. Полный Xcode не нужен."
fi

SWIFT_MAJOR="$(swift -version 2>&1 | sed -n 's/.*Swift version \([0-9][0-9]*\).*/\1/p' | head -1)"
if [ -z "$SWIFT_MAJOR" ] || [ "$SWIFT_MAJOR" -lt 6 ]; then
    fail "Нужен Swift 6 или новее, найден: $(swift -version 2>&1 | head -1)

Обновите инструменты разработчика:

    sudo rm -rf /Library/Developer/CommandLineTools
    xcode-select --install"
fi

# --- Куда ставим ------------------------------------------------------------

DESTINATION="/Applications"
if [ ! -w "$DESTINATION" ]; then
    DESTINATION="$HOME/Applications"
    # 755, иначе Launch Services не сможет прочитать пакет и сообщит об этом
    # как о «пропавшем исполняемом файле», хотя файл на месте.
    mkdir -p "$DESTINATION"
    chmod u+rwx,go+rx "$DESTINATION" 2>/dev/null || true
    echo "Папка «Программы» недоступна для записи, ставлю в $DESTINATION"
fi
TARGET="$DESTINATION/$APP_NAME"

# --- Сборка -----------------------------------------------------------------

echo "Собираю Curty…"
# Молча при успехе, но с полным логом при неудаче: подписи и сборка пишут
# много служебного вывода, в котором настоящая ошибка иначе теряется.
BUILD_LOG="$(mktemp)"
if ! "$ROOT/Scripts/build-app.sh" release >"$BUILD_LOG" 2>&1; then
    cat "$BUILD_LOG" >&2
    rm -f "$BUILD_LOG"
    fail "Сборка не удалась, вывод выше."
fi
rm -f "$BUILD_LOG"
[ -d "$BUILT_APP" ] || fail "Сборка не создала $BUILT_APP."

# --- Установка --------------------------------------------------------------

# Сначала вежливо: по сигналу applicationWillTerminate не вызывается, и
# несохранённая правка заметки теряется. pkill остаётся как запасной вариант.
osascript -e 'tell application id "dev.curty.app" to quit' >/dev/null 2>&1 || true
sleep 2
pkill -f "$APP_NAME/Contents/MacOS/Curty" 2>/dev/null || true
sleep 1

# Подстраховка перед удалением: путь должен указывать именно на наш бандл.
case "$TARGET" in
    */"$APP_NAME") rm -rf "$TARGET" ;;
    *) fail "Отказываюсь удалять $TARGET — это не $APP_NAME." ;;
esac

cp -R "$BUILT_APP" "$TARGET"
open "$TARGET" 2>/dev/null || true
sleep 2

# Скопировать пакет мало: если Launch Services не может его прочитать, macOS
# сообщает «The executable is missing», хотя дело в правах на каталог.
if ! pgrep -f "$APP_NAME/Contents/MacOS/Curty" >/dev/null 2>&1; then
    echo
    echo "Приложение скопировано в $TARGET, но не запустилось." >&2
    echo >&2
    echo "Чаще всего Launch Services не может прочитать каталог установки." >&2
    echo "Права сейчас: $(ls -ld "$DESTINATION" | awk '{print $1}')" >&2
    echo "Нужен доступ на чтение и выполнение:" >&2
    echo >&2
    echo "    chmod go+rx \"$DESTINATION\" && open \"$TARGET\"" >&2
    exit 1
fi

# --- Запускатель обновления -------------------------------------------------

# Кнопка «Обновить» в настройках запускает файл отсюда. Это штатная папка для
# скриптов песочных приложений: она лежит ВНЕ контейнера, и запуск из неё идёт
# вне песочницы. Внутрь контейнера класть нельзя — macOS помечает его целиком
# карантином, и Gatekeeper объявляет любой запуск оттуда повреждённым.
# Путь обязан совпадать с UpdatePolicy.launcherName и способом, которым
# приложение спрашивает .applicationScriptsDirectory.
SCRIPTS_DIRECTORY="$HOME/Library/Application Scripts/dev.curty.app"
if mkdir -p "$SCRIPTS_DIRECTORY" 2>/dev/null; then
    LAUNCHER="$SCRIPTS_DIRECTORY/update.sh"
    # Здесь только переход: сама логика обновления живёт в репозитории, её
    # видно, её можно прочитать, и она приезжает вместе с git pull. Терминал
    # нужен, чтобы работа пережила перезапуск Curty и была видна человеку.
    printf '#!/bin/bash\nexec /usr/bin/open -a Terminal %q/Scripts/update.command\n' "$ROOT" > "$LAUNCHER"
    chmod 700 "$LAUNCHER"
    # Карантин на самой папке достаётся ей по наследству и мешает запуску.
    # Это обычный каталог в Library, а не контейнер, — снимать его безопасно.
    xattr -cr "$SCRIPTS_DIRECTORY" 2>/dev/null || true
    # Остаток предыдущей попытки: запускатель какое-то время жил в контейнере,
    # где его блокировал Gatekeeper.
    rm -f "$HOME/Library/Containers/dev.curty.app/Data/Library/Application Support/curty/update.command"
else
    echo "warning: не удалось подготовить кнопку обновления, обновляйтесь через git pull && Scripts/install.sh" >&2
fi

echo
echo "Готово: $TARGET"
echo "Иконка щита появится в строке меню — наведите курсор на вырез экрана."
echo
echo "Что дальше:"
echo "  • macOS спросит разрешение на управление Spotify или Music — оно нужно для вкладки «Медиа»."
echo "  • Обновиться: git pull && Scripts/install.sh — данные сохранятся."
