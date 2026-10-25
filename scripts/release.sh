#!/usr/bin/env bash
# Publica uma versão nova do GoatRemote: o APK do Android e a IPA do iPhone, com a mesma versão.
#   scripts/release.sh 0.2.0 "What changed (in English)"
# O push do "Versão X" faz o CI compilar a IPA (.github/workflows/ios.yml) e espera-se por ela. Ficam com nome fixo:
# releases/latest/download/GoatRemote.apk e GoatRemote.ipa.
# Precisa de: android/keystore.properties (a chave GOAT, fora do git) e o `gh` com acesso ao repositório.
set -euo pipefail

VERSION="${1:?Uso: scripts/release.sh <versão> [notas]}"
NOTES="${2:-}"
REPO="GOAThings/GoatRemote"
cd "$(dirname "$0")/.."

if [ -n "$(git status --porcelain)" ]; then
    echo "Há alterações por gravar: faz commit primeiro." >&2
    exit 1
fi
[ -f android/keystore.properties ] || { echo "Falta o android/keystore.properties (a chave de assinatura)." >&2; exit 1; }

# versionCode sobe sempre 1; versionName é o que se pediu. O iPhone fica com a mesma versão (o build é o versionCode).
code=$(grep -oP 'versionCode = \K[0-9]+' android/app/build.gradle.kts)
sed -i "s/versionCode = $code/versionCode = $((code + 1))/; s/versionName = \"[^\"]*\"/versionName = \"$VERSION\"/" android/app/build.gradle.kts
sed -i "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION\"/; s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$((code + 1))\"/" ios/project.yml

(cd android && ./gradlew -q :app:testDebugUnitTest :app:assembleRelease)
mkdir -p build
# O mapeamento do R8 desta versão (só no PC): sem ele, os crashes vêm com nomes ofuscados.
cp android/app/build/outputs/mapping/release/mapping.txt "build/mapping-$VERSION.txt"
cp android/app/build/outputs/apk/release/app-release.apk build/GoatRemote.apk

git commit -qam "Versão $VERSION"
git tag -a "v$VERSION" -m "Versão $VERSION"  # anotada: o --follow-tags só envia tags anotadas
git push -q --follow-tags
sha=$(git rev-parse HEAD)

echo "À espera da IPA no CI…"
run=""
for _ in $(seq 60); do
    run=$(gh run list -R "$REPO" -w ios.yml -c "$sha" -L1 --json databaseId -q '.[0].databaseId' || true)
    [ -n "$run" ] && break
    sleep 5
done
[ -n "$run" ] || { echo "O build do iPhone não arrancou." >&2; exit 1; }
gh run watch "$run" -R "$REPO" -i 20 --exit-status >/dev/null
rm -rf build/ipa-download
gh run download "$run" -R "$REPO" -n GoatRemote-ipa -D build/ipa-download
mv build/ipa-download/GoatRemote.ipa build/GoatRemote.ipa
rm -rf build/ipa-download
got=$(unzip -p build/GoatRemote.ipa Payload/GoatRemote.app/Info.plist | python3 -c "import plistlib,sys; print(plistlib.loads(sys.stdin.buffer.read())['CFBundleShortVersionString'])")
[ "$got" = "$VERSION" ] || { echo "A IPA é a versão $got, não a $VERSION." >&2; exit 1; }

gh release create "v$VERSION" build/GoatRemote.apk build/GoatRemote.ipa --repo "$REPO" --title "GoatRemote $VERSION" \
    --notes "${NOTES:-Version $VERSION}"
echo "Publicada a $VERSION em https://github.com/$REPO/releases"
