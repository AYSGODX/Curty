#!/bin/bash
# Создаёт локальный сертификат для подписи Curty.
#
# Зачем: у разово подписанной (ad-hoc) сборки требование подписи — хеш её
# содержимого. Он меняется при каждой пересборке, macOS считает приложение
# новым и сбрасывает всё, что вы ему разрешили: доступ к календарю, управление
# Spotify и Music. С собственным сертификатом требование становится «тот же
# идентификатор, тот же сертификат», и разрешения переживают обновление.
#
# То же самое можно сделать руками через «Связку ключей» → «Ассистент
# сертификации» → «Создать сертификат», см. README.
set -euo pipefail

NAME="${1:-Curty Self-Signed}"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$NAME\""; then
    echo "Сертификат «$NAME» уже есть — делать ничего не нужно."
    echo "Запустите Scripts/install.sh, сборка подпишется им."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# LibreSSL из системы, а не свежий OpenSSL из Homebrew: последний упаковывает
# PKCS#12 шифрами, которые security import на macOS не читает.
OPENSSL=/usr/bin/openssl

# Пароль временный и случайный: он нужен только чтобы перенести ключ из файла
# в связку. С пустым паролем macOS отвергает контейнер — проверено.
PASSPHRASE="$($OPENSSL rand -hex 16)"

echo "Создаю сертификат «$NAME»…"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/bundle.p12" -passout "pass:$PASSPHRASE" -name "$NAME" 2>/dev/null

security import на macOS не читает.
OPENSSL=/usr/bin/openssl

cat > "$WORK/openssl.cnf" <<CONFIG
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no

[ dn ]
CN = $NAME

[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONFIG

echo "Создаю сертификат «$NAME»…"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -config "$WORK/openssl.cnf" 2>/dev/null
"$OPENSSL" pkcs12 -export -legacy \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/bundle.p12" -passout pass: -name "$NAME" 2>/dev/null \
    || "$OPENSSL" pkcs12 -export \
        -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -out "$WORK/bundle.p12" -passout pass: -name "$NAME"

# -T разрешает codesign пользоваться ключом молча: без этого macOS спрашивала бы
# подтверждение при каждой сборке.
security import "$WORK/bundle.p12" -k "$LOGIN_KEYCHAIN" -P "$PASSPHRASE" -T /usr/bin/codesign >/dev/null

echo
echo "Сейчас macOS спросит пароль — она добавляет сертификат в доверенные."
echo "Это нужно, чтобы система считала подпись действительной."
security add-trusted-cert -p codeSign -k "$LOGIN_KEYCHAIN" "$WORK/cert.pem"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$NAME\""; then
    echo
    echo "Готово. Теперь запустите установку — она подпишет сборку этим сертификатом:"
    echo
    echo "    Scripts/install.sh"
    echo
    echo "Разрешения слетят ещё один, последний раз: подпись меняется. Выдайте их"
    echo "заново — дальше они переживут любое обновление."
else
    echo
    echo "Сертификат создан, но система пока не считает его пригодным для подписи." >&2
    echo "Доверие можно проставить вручную: откройте «Связку ключей»" >&2
    echo >&2
    echo "    open \"/System/Library/CoreServices/Applications/Keychain Access.app\"" >&2
    echo >&2
    echo "найдите «$NAME» на вкладке «Мои сертификаты», откройте, разверните" >&2
    echo "«Доверие» и поставьте «Подписывание кода» → «Всегда доверять»." >&2
    exit 1
fi
