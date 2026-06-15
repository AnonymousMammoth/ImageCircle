/**
 * ImageCircle web app entry point.
 */

(function() {
    async function restoreSession() {
        state.isLoadingAuth = true;
        try {
            const user = await fetchMe();
            if (user && user.id) {
                state.setAuthFromCookie(user);
            } else {
                state.clearAuth();
            }
        } catch (err) {
            state.clearAuth();
        } finally {
            state.isLoadingAuth = false;
        }
    }

    async function init() {
        // Listen for auth required events
        window.addEventListener('circle:authrequired', () => {
            state.clearAuth();
            router.navigate('/login');
        });

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
