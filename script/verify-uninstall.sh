#!/bin/bash

# Verify SyncTV Uninstallation Script
# This script checks if all SyncTV components have been removed

echo "=========================================="
echo "  SyncTV Uninstallation Verification"
echo "=========================================="
echo ""

all_clean=true

# Check binary
echo "Checking binary files..."
if [ -f "/usr/bin/synctv" ]; then
    echo "✗ /usr/bin/synctv still exists"
    all_clean=false
else
    echo "✓ /usr/bin/synctv removed"
fi

# Check management scripts
echo ""
echo "Checking management scripts..."
for script in synctv synctv-menu synctv-ssl synctv-uninstall; do
    if [ -f "/usr/local/bin/$script" ] || [ -L "/usr/local/bin/$script" ]; then
        echo "✗ /usr/local/bin/$script still exists"
        all_clean=false
    else
        echo "✓ /usr/local/bin/$script removed"
    fi
done

# Check systemd service
echo ""
echo "Checking systemd service..."
if [ -f "/etc/systemd/system/synctv.service" ]; then
    echo "✗ /etc/systemd/system/synctv.service still exists"
    all_clean=false
else
    echo "✓ /etc/systemd/system/synctv.service removed"
fi

if systemctl list-unit-files | grep -q "synctv.service"; then
    echo "✗ synctv.service still registered in systemd"
    all_clean=false
else
    echo "✓ synctv.service not registered in systemd"
fi

# Check data directory
echo ""
echo "Checking data directory..."
if [ -d "/opt/synctv" ]; then
    echo "○ /opt/synctv still exists (may be intentional)"
else
    echo "✓ /opt/synctv removed"
fi

# Check command availability
echo ""
echo "Checking command availability..."
if command -v synctv >/dev/null 2>&1; then
    echo "✗ 'synctv' command still available"
    echo "  Location: $(which synctv)"
    echo "  Note: You may need to restart your shell"
    all_clean=false
else
    echo "✓ 'synctv' command not found"
fi

# Summary
echo ""
echo "=========================================="
if [ "$all_clean" = true ]; then
    echo "✓ All SyncTV components removed successfully!"
else
    echo "⚠ Some components still exist"
    echo ""
    echo "If you see errors above, try:"
    echo "  1. Close and reopen your terminal"
    echo "  2. Run: hash -r (to clear command cache)"
    echo "  3. Manually remove remaining files"
fi
echo "=========================================="
