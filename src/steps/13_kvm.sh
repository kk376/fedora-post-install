# ==============================================================================
# Step 13: KVM/QEMU Virtualization
# ==============================================================================
setup_kvm() {
    log "Setting up KVM/QEMU Virtualization..."

    local kvm_supported=true
    if [[ "$SYS_ARCH" == "x86_64" ]]; then
        grep -Eq 'vmx|svm' /proc/cpuinfo &>/dev/null || kvm_supported=false
    elif [[ ! -e /dev/kvm ]]; then
        kvm_supported=false
    fi

    if ! $kvm_supported; then
        warn "Hardware virtualization support (VT-x/AMD-V or /dev/kvm) not detected"
        if ! confirm "Continue installing KVM packages anyway?" "N"; then
            step_complete "KVM (skipped)"
            return 0
        fi
    fi

    run_sudo dnf install -y --skip-unavailable \
        qemu-kvm libvirt virt-install virt-manager libvirt-devel virt-top guestfs-tools gnome-boxes

    # Enable modern modular libvirt socket activation
    run_sudo systemctl disable --now libvirtd.service 2>/dev/null || true
    run_sudo systemctl enable --now virtqemud.socket virtnetworkd.socket virtstoraged.socket 2>/dev/null || true

    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        run_sudo firewall-cmd --add-service=libvirt --permanent 2>/dev/null || true
        run_sudo firewall-cmd --reload 2>/dev/null || true
    fi

    if confirm "Install VirtIO paravirtualized drivers for Windows guest VMs?" "N"; then
        run_sudo wget -q https://fedorapeople.org/groups/virt/virtio-win/virtio-win.repo \
            -O /etc/yum.repos.d/virtio-win.repo 2>/dev/null || true
        run_sudo dnf install -y --skip-unavailable virtio-win || warn "VirtIO install failed"
    fi

    run_sudo usermod -aG libvirt,kvm "${USER:-$(id -un)}"

    # Ensure LIBVIRT_DEFAULT_URI is present across Bash, Zsh, and Fish
    if ! $DRY_RUN; then
        if [[ -f "$HOME/.bashrc" ]] && ! grep -q "LIBVIRT_DEFAULT_URI" "$HOME/.bashrc"; then
            backup_file "$HOME/.bashrc"
            echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> "$HOME/.bashrc"
        fi
        if [[ -f "$HOME/.zshrc" ]] && ! grep -q "LIBVIRT_DEFAULT_URI" "$HOME/.zshrc"; then
            backup_file "$HOME/.zshrc"
            echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> "$HOME/.zshrc"
        fi
        if [[ -f "$HOME/.config/fish/config.fish" ]] && ! grep -q "LIBVIRT_DEFAULT_URI" "$HOME/.config/fish/config.fish"; then
            backup_file "$HOME/.config/fish/config.fish"
            echo 'set -gx LIBVIRT_DEFAULT_URI "qemu:///system"' >> "$HOME/.config/fish/config.fish"
        fi
    fi

    step_complete "KVM/QEMU Virtualization configured"
}

