while read -r dep ; do
    if [ -z "$dep" ] ; then
        continue
    fi
    echo "Installing $dep ..."
    if ! pip install "$dep" ; then
        echo "Failed to install $dep"
        break
    fi
done <requirements-windows.lock