/**
 * Non-dismissible forced password change modal.
 */

const forcePasswordChangeComponent = {
    _currentPassword: null,

    setCurrentPassword(password) {
        this._currentPassword = password || null;
    },

    render(container) {
        clearEl(container);
        container.className = 'login-screen';

        const logo = createEl('div', { className: 'login-logo', innerHTML: shell.icons.lock });
        const title = createEl('h1', { className: 'login-title', text: 'Change Your Password' });
        const subtitle = createEl('p', {
            style: 'text-align:center;color:var(--text-secondary);margin-bottom:32px;max-width:320px;'
        });
        subtitle.textContent = 'Your account was created with a temporary password. Set your own to continue.';

        const form = createEl('form', { className: 'login-form' });

        const newGroup = createEl('div', { className: 'form-group' });
        newGroup.appendChild(createEl('label', { text: 'New Password' }));
        const newInput = createEl('input', { type: 'password', required: true, autocomplete: 'new-password' });
        newGroup.appendChild(newInput);

        const confirmGroup = createEl('div', { className: 'form-group' });
        confirmGroup.appendChild(createEl('label', { text: 'Confirm New Password' }));
        const confirmInput = createEl('input', { type: 'password', required: true, autocomplete: 'new-password' });
        confirmGroup.appendChild(confirmInput);

        const errorEl = createEl('div', { className: 'error-text' });
        const submitBtn = createEl('button', { type: 'submit', className: 'btn btn-primary', text: 'Set Password' });

        form.appendChild(newGroup);
        form.appendChild(confirmGroup);
        form.appendChild(errorEl);
        form.appendChild(submitBtn);

        form.addEventListener('submit', (e) => {
            e.preventDefault();
            this.submit(newInput.value, confirmInput.value, errorEl, submitBtn);
        });

        container.appendChild(logo);
        container.appendChild(title);
        container.appendChild(subtitle);
        container.appendChild(form);
    },

    async submit(newPassword, confirmPassword, errorEl, submitBtn) {
        setText(errorEl, '');
        const strengthError = validatePasswordStrength(newPassword);
        if (strengthError) {
            setText(errorEl, strengthError);
            return;
        }
        if (newPassword !== confirmPassword) {
            setText(errorEl, 'Passwords do not match.');
            return;
        }

        const currentPassword = this._currentPassword;
        this._currentPassword = null;

        submitBtn.disabled = true;
        submitBtn.innerHTML = '<span class="spinner"></span>';

        try {
            const data = await changePassword(currentPassword, newPassword);
            if (data && data.token) {
                state.token = data.token;
            }
            const me = await fetchMe();
            state.updateUser(me);
            state.requiresPasswordChange = false;
            router.navigate('/');
            shell.handleRoute();
        } catch (err) {
            setText(errorEl, err.message);
            submitBtn.disabled = false;
            submitBtn.textContent = 'Set Password';
        }
    }
};
