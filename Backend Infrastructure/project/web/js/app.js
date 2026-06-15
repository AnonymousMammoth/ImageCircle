/**
 * ImageCircle web app entry point.
 */

(function() {
    function init() {
        // Listen for auth required events
        window.addEventListener('circle:authrequired', () => {
            state.clearAuth();
            router.navigate('/login');
        });

        // Initialize router; shell will render on first route event
        router.init();

        // If not authenticated, force login route
        if (!state.isAuthenticated) {
            const path = router.getPath();
            if (path !== '/login' && path !== '/setup') {
                router.navigate('/login');
            } else {
                shell.render();
            }
        } else {
            shell.render();
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
