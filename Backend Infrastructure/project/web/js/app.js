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

    async function refreshNotificationCount() {
        if (!state.isAuthenticated) {
            state.setNotificationCount(0);
            return;
        }
        try {
            const count = await fetchUnreadNotificationCount();
            state.setNotificationCount(count);
            if (shell && shell.updateNotificationBadge) {
                shell.updateNotificationBadge();
            }
        } catch (_) {
            // Non-fatal; badge simply won't update.
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
                // Desktop Safari/PWAs often refuse to send the HttpOnly cookie for
                // <img> subresources, so fetch a JWT now and use it for media URLs.
                try {
                    const refreshed = await apiPost('/auth/refresh', {});
                    if (refreshed && refreshed.token) {
                        state.token = refreshed.token;
                    }
                } catch (_) {
                    // Cookie auth still works for fetch requests; media just falls
                    // back to initials if the cookie is not sent for images.
                }
                await refreshNotificationCount();
                return;
            }

            state.clearAuth();
        } finally {
            state.isLoadingAuth = false;
        }
    }

    function registerServiceWorker() {
        if ('serviceWorker' in navigator) {
            navigator.serviceWorker.register('/sw.js').catch((err) => {
                console.warn('Service worker registration failed', err);
            });
        }
    }

    function detectIosStandalone() {
        if (window.navigator.standalone === true) {
            document.body.classList.add('ios-standalone');
        }
    }

    async function init() {
        // Convert path-based deep links to hash routes before the router runs.
        syncPathToHash();

        // Register PWA service worker early.
        registerServiceWorker();

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

        // Refresh badge when the route changes.
        window.addEventListener('circle:route', () => {
            refreshNotificationCount();
        });

        detectIosStandalone();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
