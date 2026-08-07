#!/bin/bash
set -euo pipefail

# Кнопка «Обновить» в настройках Curty открывает именно этот файл. Двойной клик
# по нему в Finder делает ровно то же самое: приложение в песочнице не может ни
# собрать себя, ни записать в /Applications, а Терминал работает без неё.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Обновление Curty"
echo "Репозиторий: $ROOT"
echo

if [ ! -d "$ROOT/.git" ]; then
    echo "Это не git-репозиторий, обновляться неоткуда." >&2
    echo "Склонируйте заново: git clone https://github.com/AYSGODX/Curty.git" >&2
    exit 1
fi

cd "$ROOT"
git pull --ff-only
bash Scripts/install.sh

echo
echo "Готово. Окно можно закрыть."
