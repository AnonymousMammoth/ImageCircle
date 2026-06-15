/**
 * Login and first-admin setup screen.
 */

const loginComponent = {
    render(container) {
        clearEl(container);
        container.className = 'login-screen';

        // The web UI is served from the same origin as the API, so default to it.
        if (!state.serverURL) {
            state.serverURL = window.location.origin;
        }

        const logo = createEl('div', { className: 'login-logo', innerHTML: shell.icons.profileFill });
        const title = createEl('h1', { className: 'login-title', text: 'ImageCircle' });

        const form = createEl('form', { className: 'login-form', id: 'login-form' });

        const usernameGroup = createEl('div', { className: 'form-group' });
        const usernameLabel = createEl('label', { text: 'Username' });
        const usernameInput = createEl('input', {
            type: 'text',
            id: 'login-username',
            required: true,
            autocomplete: 'username'
        });
        usernameGroup.appendChild(usernameLabel);
        usernameGroup.appendChild(usernameInput);

        const passwordGroup = createEl('div', { className: 'form-group' });
        const passwordLabel = createEl('label', { text: 'Password' });
        const passwordInput = createEl('input', {
            type: 'password',
            id: 'login-password',
            required: true,
            autocomplete: 'current-password'
        });
        passwordGroup.appendChild(passwordLabel);
        passwordGroup.appendChild(passwordInput);

        const errorEl = createEl('div', { className: 'error-text', id: 'login-error' });

        const submitBtn = createEl('button', {
            type: 'submit',
            className: 'btn btn-primary',
            id: 'login-submit'
        });
        submitBtn.textContent = 'Log In';

        form.appendChild(usernameGroup);
        form.appendChild(passwordGroup);
        form.appendChild(errorEl);
        form.appendChild(submitBtn);

        form.addEventListener('submit', (e) => {
            e.preventDefault();
            this.handleLogin(usernameInput.value.trim(), passwordInput.value, errorEl, submitBtn);
        });

        container.appendChild(logo);
        container.appendChild(title);
        container.appendChild(form);

        // Check if first setup may be available and no users exist.
        this.checkSetupHint(container);
    },

    async checkSetupHint(container) {
        try {
            const response = await fetch('/api/admin/setup', { method: 'GET', credentials: 'same-origin' });
            if (response.status !== 200) return; // setup already complete or error
            const hint = createEl('p', {
                style: 'font-size:13px;color:var(--text-secondary);margin-top:24px;text-align:center;'
            });
            hint.innerHTML = 'First admin? Use <a href="#/setup">setup</a>.';
            container.appendChild(hint);
        } catch (_) {
            // ignore
        }
    },

    async handleLogin(username, password, errorEl, submitBtn) {
        setText(errorEl, '');
        submitBtn.disabled = true;
        submitBtn.innerHTML = '<span class="spinner"></span>';

        try {
            const data = await login(username, password);
            if (!data || !data.token || !data.user) {
                throw new Error('Invalid response from server');
            }
            state.setAuth(data);
            if (state.requiresPasswordChange) {
                forcePasswordChangeComponent.setCurrentPassword(password);
                router.navigate('/force-password-change');
            } else {
                router.navigate('/');
            }
        } catch (err) {
            setText(errorEl, err.message);
            submitBtn.disabled = false;
            submitBtn.textContent = 'Log In';
        }
    }
};

/* ---------- First-admin setup screen ---------- */

const setupComponent = {
    render(container) {
        clearEl(container);
        container.className = 'login-screen';

        const title = createEl('h1', { className: 'login-title', text: 'Setup Admin' });
        const form = createEl('form', { className: 'login-form' });

        const usernameGroup = createEl('div', { className: 'form-group' });
        const usernameInput = createEl('input', { type: 'text', required: true, placeholder: 'Admin username' });
        usernameGroup.appendChild(createEl('label', { text: 'Username' }));
        usernameGroup.appendChild(usernameInput);

        const passwordGroup = createEl('div', { className: 'form-group' });
        const passwordInput = createEl('input', { type: 'password', required: true, placeholder: 'Strong password' });
        passwordGroup.appendChild(createEl('label', { text: 'Password' }));
        passwordGroup.appendChild(passwordInput);

        const errorEl = createEl('div', { className: 'error-text' });
        const submitBtn = createEl('button', { type: 'submit', className: 'btn btn-primary', text: 'Create Admin' });

        form.appendChild(usernameGroup);
        form.appendChild(passwordGroup);
        form.appendChild(errorEl);
        form.appendChild(submitBtn);

        form.addEventListener('submit', (e) => {
            e.preventDefault();
            this.handleSetup(usernameInput.value.trim(), passwordInput.value, errorEl, submitBtn);
        });

        container.appendChild(title);
        container.appendChild(form);
    },

    async handleSetup(username, password, errorEl, submitBtn) {
        setText(errorEl, '');
        submitBtn.disabled = true;
        submitBtn.innerHTML = '<span class="spinner"></span>';
        try {
            const data = await apiPost('/admin/setup', { username, password });
            state.setAuth(data);
            router.navigate('/');
        } catch (err) {
            setText(errorEl, err.message);
            submitBtn.disabled = false;
            submitBtn.textContent = 'Create Admin';
        }
    }
};

window.addEventListener('circle:route', () => {
    const path = router.getPath();
    if (path === '/setup') {
        const content = document.getElementById('main-content');
        if (content) setupComponent.render(content);
    }
});
