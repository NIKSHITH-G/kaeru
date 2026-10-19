# Code signing for Kaeru builds (sourced by build-app.sh).
#
# Every build is signed with the same self-signed "Kaeru Signing" certificate, so macOS sees updates as
# the same app and keeps its permissions (Accessibility, Automation) instead of resetting them.
# The certificate comes from KAERU_SIGNING_P12_PATH + KAERU_SIGNING_PASSWORD (CI), or from the local copy in
# ~/Library/Application Support/Kaeru Signing. Without it, builds fall back to ad hoc signing.
# It's imported into a temporary keychain, so the login keychain is never touched.

setup_signing() {
    local p12="${KAERU_SIGNING_P12_PATH:-$HOME/Library/Application Support/Kaeru Signing/kaeru-signing.p12}"
    local pass="${KAERU_SIGNING_PASSWORD:-}"
    if [ -z "$pass" ] && [ -f "${p12%.p12}.pass" ]; then pass=$(cat "${p12%.p12}.pass"); fi

    CODESIGN_IDENTITY="-"
    CODESIGN_KEYCHAIN=""
    if [ -f "$p12" ] && [ -n "$pass" ]; then
        local kc_pass
        kc_pass=$(openssl rand -hex 12)
        CODESIGN_KEYCHAIN="$(mktemp -d)/kaeru-signing.keychain-db"
        security create-keychain -p "$kc_pass" "$CODESIGN_KEYCHAIN"
        security set-keychain-settings "$CODESIGN_KEYCHAIN"
        security unlock-keychain -p "$kc_pass" "$CODESIGN_KEYCHAIN"
        security import "$p12" -k "$CODESIGN_KEYCHAIN" -P "$pass" -T /usr/bin/codesign >/dev/null
        security set-key-partition-list -S apple-tool:,apple: -s -k "$kc_pass" "$CODESIGN_KEYCHAIN" >/dev/null
        # On CI build machines codesign only finds keys in keychains on the search list
        # (otherwise: errSecInternalComponent). Locally the search list is left alone.
        if [ -n "${CI:-}" ]; then
            local existing
            existing=$(security list-keychains -d user | tr -d '"' | xargs)
            # shellcheck disable=SC2086
            security list-keychains -d user -s "$CODESIGN_KEYCHAIN" $existing
            security unlock-keychain -p "$kc_pass" "$CODESIGN_KEYCHAIN"
        fi
        security find-identity -p codesigning "$CODESIGN_KEYCHAIN" | sed -n '1,3p'
        CODESIGN_IDENTITY="Kaeru Signing"
        trap 'security delete-keychain "$CODESIGN_KEYCHAIN" 2>/dev/null' EXIT
        echo "Signing with the Kaeru Signing certificate"
    else
        echo "Signing ad hoc (no Kaeru signing certificate found; permissions will reset on update)"
    fi
    export CODESIGN_IDENTITY CODESIGN_KEYCHAIN
}

sign() {
    if [ -n "$CODESIGN_KEYCHAIN" ]; then
        codesign --force --sign "$CODESIGN_IDENTITY" --keychain "$CODESIGN_KEYCHAIN" "$@"
    else
        codesign --force --sign "$CODESIGN_IDENTITY" "$@"
    fi
}
