/**
 * ImageCircle web app entry point.
 */

(function() {
    function syncPathToHash() {
        // The router is hash-based, but the backend serves the SPA shell for
        // any path. Convert a path-style deep link (e.g. /profile/3) into a
        // hash route (e.g. #/profile/3) without reloading the page.
        const hash = window.location.hash;
        const path = window.location.pathname;
        const search = window.location.search || '';
        if ((!hash || hash === '#') && path && path !== '/') {
            history.replaceState(null, '', '/#' + path + search);
        }
    }

    async function restoreSession() {
        state.isLoadingAuth = true;
        try {
            // First try the HttpOnly session cookie.
            let user = null;
            try { user = await fetchMe(); } catch (_) { user = null; }
            if (user && user.id) {
                state.setAuthFromCookie(user);
                return;
            }

            // Fallback to a persisted JWT for browsers/environments where the
            // cookie isn't available (e.g. some desktop browsers, incognito).
            const token = state.loadPersistedToken();
            if (token) {
                state.token = token;
                try { user = await fetchMe(); } catch (_) { user = null; }
                if (user && user.id) {
                    state.setAuth({ token, user });
                    return;
                }
            }

            state.clearAuth();
        } finally {
            state.isLoadingAuth = false;
        }
    }

    async function init() {
        // Convert path-based deep links to hash routes before the router runs.
        syncPathToHash();

        // Listen for auth required events
        window.addEventListener('circle:authrequired', () => {
            state.clearAuth();
            router.navigate('/login');
        });

        // Always attempt to restore the session from the HttpOnly cookie first.
        await restoreSession();

        // Render the shell so route handlers have a layout to work with.
        shell.render();

        // Initialize router; shell will render on first route event.
        router.init();

        // If still not authenticated, ensure we end up on login.
        if (!state.isAuthenticated) {
            const path = router.getPath();
            if (path !== '/login' && path !== '/setup') {
                router.navigate('/login');
            }
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
