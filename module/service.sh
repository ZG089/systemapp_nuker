MODDIR="/data/adb/modules/system_app_nuker"
PERSIST_DIR="/data/adb/system_app_nuker"
APP_LIST="$PERSIST_DIR/app_list.json"
REMOVE_LIST="$PERSIST_DIR/nuke_list.json"
ICON_DIR="$PERSIST_DIR/icons"

# import config
uninstall_fallback=false
[ -f "$PERSIST_DIR/config.sh" ] && . $PERSIST_DIR/config.sh

aapt() { "$MODDIR/common/aapt" "$@"; }


until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

[ ! -d "$PERSIST_DIR" ] && mkdir -p "$PERSIST_DIR"

# reset bootcount
echo "BOOTCOUNT=0" > "$PERSIST_DIR/count.sh"
chmod 755 "$PERSIST_DIR/count.sh"

# ensure the remove list exists
[ -s "$REMOVE_LIST" ] || echo "[]" > "$REMOVE_LIST"

# get list of app paths to be removed
NUKED_PATHS=$(grep -o "\"app_path\":.*" "$REMOVE_LIST" | awk -F"\"" '{print $4}')

create_applist() {
    echo "[" > "$APP_LIST"

    system_app_path="/system/app /system/priv-app /vendor/app /product/app /product/priv-app /system_ext/app /system_ext/priv-app"
    for path in $system_app_path; do
        find "$path" -maxdepth 2 -type f -name "*.apk" | while read APK_PATH; do
            # skip if already on app list
            if grep -q "$APK_PATH" "$APP_LIST"; then
                continue
            fi
            
            # skip if path is in nuke list
            if echo "$NUKED_PATHS" | grep -q "$APK_PATH"; then
                continue
            fi

            [ -z "$PKG_LIST" ] && PKG_LIST=$(pm list packages -f)
            PACKAGE_NAME=$(echo "$PKG_LIST" | grep "$APK_PATH" | awk -F= '{print $2}')
            [ -z "$PACKAGE_NAME" ] && PACKAGE_NAME=$(aapt dump badging "$APK_PATH" 2>/dev/null | grep "package:" | awk -F' ' '{print $2}' | sed "s/^name='\([^']*\)'.*/\1/")
            [ -z "$PACKAGE_NAME" ] && continue

            APP_NAME=$(aapt dump badging "$APK_PATH" 2>/dev/null | grep "application-label:" | sed "s/application-label://g; s/'//g")
            [ -z "$APP_NAME" ] && APP_NAME="$PACKAGE_NAME"

            echo "  {\"app_name\": \"$APP_NAME\", \"package_name\": \"$PACKAGE_NAME\", \"app_path\": \"$APK_PATH\"}," >> "$APP_LIST"
            
            ICON_PATH=$(aapt dump badging "$APK_PATH" 2>/dev/null | grep "application:" | awk -F "icon=" '{print $2}' | sed "s/'//g")
            # Extract the icon if it exists
            ICON_FILE="$ICON_DIR/$PACKAGE_NAME.png"

            if [ -n "$ICON_PATH" ]; then
                unzip -p "$APK_PATH" "$ICON_PATH" > "$ICON_FILE"
            fi
        done
    done

    # Fallback for no package name found
    for package_name in $(pm list packages -s | sed 's/package://g'); do
        if grep -q "\"$package_name\"" "$APP_LIST"; then
            continue
        fi
        APP_NAME=$(aapt dump badging "$package_name" 2>/dev/null | grep "application-label:" | sed "s/application-label://g; s/'//g")
        [ -z "$APP_NAME" ] && APP_NAME="$package_name"

        APK_PATH=$(pm path $package_name | sed 's/package://g')
        echo "$APK_PATH" | grep -qE "/system/app|/system/priv-app|/vendor/app|/product/app|/product/priv-app|/system_ext/app|/system_ext/priv-app" || continue
        echo "  {\"app_name\": \"$APP_NAME\", \"package_name\": \"$package_name\", \"app_path\": \"$APK_PATH\"}, " >> "$APP_LIST"
    done

    sed -i '$ s/,$//' "$APP_LIST"
    echo "]" >> "$APP_LIST"
}

# ensure the icon directory exists
[ ! -d "$ICON_DIR" ] && mkdir -p "$ICON_DIR"

create_applist

# create symlink for app icon
[ ! -L "$MODDIR/webroot/link" ] && ln -s $PERSIST_DIR $MODDIR/webroot/link

# this make sure that restored app is back
for pkg in $(grep -o "\"package_name\":.*" "$APP_LIST" | awk -F"\"" '{print $4}'); do
    if ! pm path "$pkg" >/dev/null 2>&1; then
        pm install-existing "$pkg" >/dev/null 2>&1
    fi
done

# uninstall fallback if apps aint nuked at late service
# enable this on config.sh
$uninstall_fallback && {
    # remove system apps if they still exist
    for package_name in $(grep -o "\"package_name\":.*" "$REMOVE_LIST" | awk -F"\"" '{print $4}'); do
        if pm list packages | grep -qx "package:$package_name"; then
            pm uninstall -k --user 0 "$package_name" 2>/dev/null
        fi
    done
}

# EOF
