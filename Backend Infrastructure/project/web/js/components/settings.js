/**
 * Settings screen: change password, admin link, logout.
 */

const settingsComponent = {
    render(container) {
        clearEl(container);
        container.className = 'screen-scroll tab-content';

        const header = createEl('div', { className: 'top-header' });
        header.appendChild(createEl('h1', { text: 'Settings' }));
        container.appendChild(header);

        const list = createEl('div', { className: 'settings-list' });

        list.appendChild(this.sectionTitle('Account'));
        list.appendChild(this.item(shell.icons.lock, 'Change Password', null, () => this.showChangePassword()));
        list.appendChild(this.item(shell.icons.settings, 'Server', state.serverURL || window.location.origin, null));

        if (state.isAdmin) {
            list.appendChild(this.sectionTitle('Admin'));
            const adminItem = this.item(shell.icons.shield, 'Admin Panel', null, () => {
                window.location.href = '/admin';
            });
            list.appendChild(adminItem);
        }

        list.appendChild(this.sectionTitle('Danger'));
        list.appendChild(this.item(shell.icons.logout, 'Log Out', null, () => this.logout(), true));

        container.appendChild(list);
    },

    sectionTitle(title) {
        return createEl('div', { className: 'settings-section-title', text: title });
    },

    item(icon, label, value, onClick, danger) {
        const btn = createEl('button', { className: 'settings-item' + (danger ? ' danger' : '') });
        btn.innerHTML = icon;
        btn.appendChild(createEl('span', { text: label }));
        if (value) {
            btn.appendChild(createEl('span', { className: 'value', text: value }));
        }
        if (onClick) {
            btn.addEventListener('click', onClick);
        }
        return btn;
    },

    showChangePassword() {
        const overlay = createEl('div', { className: 'modal-overlay' });
        overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.remove(); });

        const sheet = createEl('div', { className: 'modal-sheet' });
        const header = createEl('div', { className: 'modal-sheet-header' });
        header.appendChild(createEl('h2', { text: 'Change Password' }));
        const closeBtn = createEl('button', { className: 'btn-icon' });
        closeBtn.innerHTML = shell.icons.close;
        closeBtn.addEventListener('click', () => overlay.remove());
        header.appendChild(closeBtn);

        const body = createEl('div', { className: 'modal-sheet-body', style: 'padding:16px;' });

        const currentGroup = createEl('div', { className: 'form-group' });
        currentGroup.appendChild(createEl('label', { text: 'Current Password' }));
        const currentInput = createEl('input', { type: 'password', autocomplete: 'current-password' });
        currentGroup.appendChild(currentInput);

        const newGroup = createEl('div', { className: 'form-group' });
        newGroup.appendChild(createEl('label', { text: 'New Password' }));
        const newInput = createEl('input', { type: 'password', autocomplete: 'new-password' });
        newGroup.appendChild(newInput);

        const confirmGroup = createEl('div', { className: 'form-group' });
        confirmGroup.appendChild(createEl('label', { text: 'Confirm New Password' }));
        const confirmInput = createEl('input', { type: 'password', autocomplete: 'new-password' });
        confirmGroup.appendChild(confirmInput);

        const errorEl = createEl('div', { className: 'error-text' });
        const successEl = createEl('div', { style: 'color:var(--success);font-size:13px;min-height:18px;' });

        const submitBtn = createEl('button', { className: 'btn btn-primary', style: 'width:100%;' });
        submitBtn.textContent = 'Update Password';
        submitBtn.addEventListener('click', () => {
            this.submitChangePassword(
                currentInput.value,
                newInput.value,
                confirmInput.value,
                errorEl,
                successEl,
                submitBtn
            );
        });

        body.appendChild(currentGroup);
        body.appendChild(newGroup);
        body.appendChild(confirmGroup);
        body.appendChild(errorEl);
        body.appendChild(successEl);
        body.appendChild(submitBtn);

        sheet.appendChild(header);
        sheet.appendChild(body);
        overlay.appendChild(sheet);
        document.body.appendChild(overlay);
    },

    async submitChangePassword(current, newPass, confirm, errorEl, successEl, btn) {
        setText(errorEl, '');
        setText(successEl, '');
        if (newPass.length < 6) {
            setText(errorEl, 'Password must be at least 6 characters.');
            return;
        }
        if (newPass !== confirm) {
            setText(errorEl, 'Passwords do not match.');
            return;
        }
        btn.disabled = true;
        btn.innerHTML = '<span class="spinner"></span>';
        try {
            const data = await changePassword(current, newPass);
            if (data && data.token) {
                state.token = data.token;
            }
            setText(successEl, 'Password updated successfully.');
            btn.textContent = 'Update Password';
            btn.disabled = false;
        } catch (err) {
            setText(errorEl, err.message);
            btn.textContent = 'Update Password';
            btn.disabled = false;
        }
    },

    async logout() {
        if (!confirmAction('Log out? Your session will be cleared.')) return;
        try {
            await logout();
        } catch (_) {}
        state.clearAuth();
        router.navigate('/login');
    }
};
