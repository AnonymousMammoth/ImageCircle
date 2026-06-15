/**
 * Main app shell with bottom tab bar.
 */

const shell = {
    root: null,

    icons: {
        home: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M2.25 12l8.954-8.955c.44-.439 1.152-.439 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75M8.25 21h8.25" /></svg>',
        homeFill: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path d="M11.47 3.84a.75.75 0 011.06 0l8.69 8.69a.75.75 0 101.06-1.06l-8.689-8.69a2.25 2.25 0 00-3.182 0l-8.69 8.69a.75.75 0 001.061 1.06l8.69-8.69z" /><path d="M12 5.432l8.159 8.159c.03.03.06.058.091.086v6.198c0 1.035-.84 1.875-1.875 1.875H15a.75.75 0 01-.75-.75v-4.5a.75.75 0 00-.75-.75h-3a.75.75 0 00-.75.75V21a.75.75 0 01-.75.75H5.625a1.875 1.875 0 01-1.875-1.875v-6.198a2.29 2.29 0 00.091-.086L12 5.43z" /></svg>',
        search: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z" /></svg>',
        create: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" /></svg>',
        profile: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0zM4.501 20.118a7.5 7.5 0 0114.998 0A17.933 17.933 0 0112 21.75c-2.676 0-5.216-.584-7.499-1.632z" /></svg>',
        profileFill: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path fill-rule="evenodd" d="M7.5 6a4.5 4.5 0 119 0 4.5 4.5 0 01-9 0zM3.751 20.105a8.25 8.25 0 0116.498 0 .75.75 0 01-.437.695A18.683 18.683 0 0112 22.5c-2.786 0-5.433-.608-7.812-1.7a.75.75 0 01-.437-.695z" clip-rule="evenodd" /></svg>',
        close: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>',
        menu: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M6.75 12a.75.75 0 11-1.5 0 .75.75 0 011.5 0zM12.75 12a.75.75 0 11-1.5 0 .75.75 0 011.5 0zM18.75 12a.75.75 0 11-1.5 0 .75.75 0 011.5 0z" /></svg>',
        heart: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M21 8.25c0-2.485-2.099-4.5-4.688-4.5-1.935 0-3.597 1.126-4.312 2.733-.715-1.607-2.377-2.733-4.313-2.733C5.1 3.75 3 5.765 3 8.25c0 7.22 9 12 9 12s9-4.78 9-12z" /></svg>',
        heartFill: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path d="M11.645 20.91l-.007-.003-.022-.012a15.247 15.247 0 01-.383-.218 25.18 25.18 0 01-4.244-3.17C4.688 15.36 2.25 12.174 2.25 8.25 2.25 5.322 4.714 3 7.688 3A5.5 5.5 0 0112 5.052 5.5 5.5 0 0116.313 3c2.973 0 5.437 2.322 5.437 5.25 0 3.925-2.438 7.111-4.739 9.256a25.175 25.175 0 01-4.244 3.17 15.247 15.247 0 01-.383.219l-.022.012-.007.004-.003.001a.752.752 0 01-.704 0l-.003-.001z" /></svg>',
        comment: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 20.25c4.97 0 9-3.694 9-8.25s-4.03-8.25-9-8.25S3 7.444 3 12c0 2.104.859 4.023 2.273 5.48.432.447.74 1.04.586 1.641a4.483 4.483 0 01-.923 1.785A5.969 5.969 0 006 21c1.282 0 2.47-.402 3.445-1.087.81.22 1.668.337 2.555.337z" /></svg>',
        send: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M6 12L3.269 3.126A59.768 59.768 0 0121.485 12 59.77 59.77 0 013.27 20.876L5.999 12zm0 0h7.5" /></svg>',
        photo: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909m-18 3.75h16.5a2.25 2.25 0 002.25-2.25V6a2.25 2.25 0 00-2.25-2.25H3.75A2.25 2.25 0 001.5 6v12a2.25 2.25 0 002.25 2.25z" /></svg>',
        text: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M7.5 8.25h9m-9 3H12m-9.75 1.51c0 1.6 1.123 2.994 2.707 3.227 1.129.166 2.27.293 3.423.379.35.026.67.21.865.501L12 21l2.755-4.133a1.14 1.14 0 01.865-.501 48.172 48.172 0 003.423-.379c1.584-.233 2.707-1.626 2.707-3.228V6.741c0-1.602-1.123-2.995-2.707-3.228A48.394 48.394 0 0012 3c-2.392 0-4.744.015-7.53.163C2.694 3.333 1.5 4.726 1.5 6.328v.83c0 1.39.6 2.7 1.55 3.596" /></svg>',
        camera: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M6.827 6.175A2.31 2.31 0 015.186 7.23c-.38.054-.757.112-1.134.175C2.999 7.58 2.25 8.507 2.25 9.574V18a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9.574c0-1.067-.75-1.994-1.802-2.169a47.865 47.865 0 00-1.134-.175 2.31 2.31 0 01-1.64-1.055l-.822-1.316a2.192 2.192 0 00-1.736-1.039 48.774 48.774 0 00-5.232 0 2.192 2.192 0 00-1.736 1.039l-.821 1.316z" /><path stroke-linecap="round" stroke-linejoin="round" d="M16.5 12.75a4.5 4.5 0 11-9 0 4.5 4.5 0 019 0zM18.75 10.5h.008v.008h-.008V10.5z" /></svg>',
        settings: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.212 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.063-.374-.313-.686-.645-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z" /><path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" /></svg>',
        logout: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M15.75 9V5.25A2.25 2.25 0 0013.5 3h-6a2.25 2.25 0 00-2.25 2.25v13.5A2.25 2.25 0 007.5 21h6a2.25 2.25 0 002.25-2.25V15M12 9l-3 3m0 0l3 3m-3-3h12.75" /></svg>',
        lock: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z" /></svg>',
        shield: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75m-3-7.036A11.959 11.959 0 013.598 6 11.99 11.99 0 003 9.749c0 5.592 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285z" /></svg>',
        trash: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0" /></svg>',
        check: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" /></svg>',
        plus: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" /></svg>',
        video: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M5.25 5.653c0-.856.917-1.398 1.667-.986l11.54 6.348a1.125 1.125 0 010 1.971l-11.54 6.347a1.125 1.125 0 01-1.667-.985V5.653z" /></svg>',
        bell: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M14.857 17.082a23.848 23.848 0 005.454-1.31A8.967 8.967 0 0118 9.75v-.7V9A6 6 0 006 9v.75a8.967 8.967 0 01-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 01-5.714 0m5.714 0a3 3 0 11-5.714 0" /></svg>',
        bellFill: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path fill-rule="evenodd" d="M5.25 9a6.75 6.75 0 0113.5 0v.75c0 2.123.8 4.057 2.118 5.52a.75.75 0 01-.297 1.206c-1.516.508-3.19.814-4.933.921a39.656 39.656 0 01-5.164 0 18.424 18.424 0 01-4.933-.921.75.75 0 01-.298-1.205A8.217 8.217 0 005.25 9.75V9zm6.006 11.394a.75.75 0 10-1.486.202c.331.996 1.274 1.704 2.48 1.704s2.149-.708 2.48-1.704a.75.75 0 00-1.486-.202c-.22.663-.854 1.106-1.994 1.106s-1.774-.443-1.994-1.106z" clip-rule="evenodd" /></svg>',
        warning: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" /></svg>',
        image: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909m-18 3.75h16.5a2.25 2.25 0 002.25-2.25V6a2.25 2.25 0 00-2.25-2.25H3.75A2.25 2.25 0 001.5 6v12a2.25 2.25 0 002.25 2.25z" /></svg>',
        quote: '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M7.5 8.25h9m-9 3H12m-9.75 1.51c0 1.6 1.123 2.994 2.707 3.227 1.129.166 2.27.293 3.423.379.35.026.67.21.865.501L12 21l2.755-4.133a1.14 1.14 0 01.865-.501 48.172 48.172 0 003.423-.379c1.584-.233 2.707-1.626 2.707-3.228V6.741c0-1.602-1.123-2.995-2.707-3.228A48.394 48.394 0 0012 3c-2.392 0-4.744.015-7.53.163C2.694 3.333 1.5 4.726 1.5 6.328v.83c0 1.39.6 2.7 1.55 3.596" /></svg>'
    },

    getTabs() {
        return [
            { id: 'home', label: 'Home', icon: 'home', activeIcon: 'homeFill' },
            { id: 'search', label: 'Search', icon: 'search', activeIcon: 'search' },
            { id: 'create', label: 'Create', icon: 'create', activeIcon: 'create' },
            { id: 'notifications', label: 'Notifications', icon: 'bell', activeIcon: 'bellFill' },
            { id: 'profile', label: 'Profile', icon: 'profile', activeIcon: 'profileFill' }
        ];
    },

    render() {
        const app = document.getElementById('app');

        if (this.root && this.root.parentNode === app) {
            this.updateActiveTab();
            this.updateDesktopSidebars();
            this.handleRoute();
            return;
        }

        clearEl(app);

        this.root = createEl('div', { className: 'screen' });

        const leftSidebar = createEl('aside', { id: 'sidebar-left', className: 'sidebar-left hidden' });
        leftSidebar.appendChild(this.renderSidebarNav());
        this.root.appendChild(leftSidebar);

        const content = createEl('main', { id: 'main-content', className: 'screen-scroll' });
        this.root.appendChild(content);

        const rightSidebar = createEl('aside', { id: 'sidebar-right', className: 'sidebar-right hidden' });
        rightSidebar.appendChild(this.renderSidebarRight());
        this.root.appendChild(rightSidebar);

        const tabBar = createEl('nav', { id: 'tab-bar', className: 'tab-bar' });
        this.getTabs().forEach(tab => {
            const active = this.getActiveTab() === tab.id;
            const btn = createEl('button', {
                className: 'tab-item' + (active ? ' active' : ''),
                'data-tab': tab.id
            });
            btn.innerHTML = this.icons[active ? tab.activeIcon : tab.icon] + '<span>' + escapeHtml(tab.label) + '</span>';
            btn.addEventListener('click', () => this.navigateTab(tab.id));
            tabBar.appendChild(btn);
        });

        this.root.appendChild(tabBar);
        app.appendChild(this.root);

        // The initial route will be handled by the router's route event.
        this.updateActiveTab();
    },

    renderSidebarNav() {
        const wrap = createEl('div', { className: 'sidebar-nav' });
        const brand = createEl('div', { className: 'sidebar-brand' });
        brand.innerHTML = this.icons.profileFill + '<span>ImageCircle</span>';
        wrap.appendChild(brand);

        const nav = createEl('nav', { className: 'sidebar-menu' });
        this.getTabs().forEach(tab => {
            const active = this.getActiveTab() === tab.id;
            const btn = createEl('button', {
                className: 'sidebar-item' + (active ? ' active' : ''),
                'data-tab': tab.id
            });
            btn.innerHTML = this.icons[active ? tab.activeIcon : tab.icon] + '<span>' + escapeHtml(tab.label) + '</span>';
            btn.addEventListener('click', () => this.navigateTab(tab.id));
            nav.appendChild(btn);
        });
        wrap.appendChild(nav);

        const createBtn = createEl('button', { className: 'sidebar-create-btn' });
        createBtn.innerHTML = shell.icons.create + '<span>New post</span>';
        createBtn.addEventListener('click', () => router.navigate('/create'));
        wrap.appendChild(createBtn);

        return wrap;
    },

    renderSidebarRight() {
        const wrap = createEl('div', { className: 'sidebar-right-content' });

        const createBtn = createEl('button', { className: 'sidebar-create-btn' });
        createBtn.innerHTML = shell.icons.create + '<span>New post</span>';
        createBtn.addEventListener('click', () => router.navigate('/create'));
        wrap.appendChild(createBtn);

        const title = createEl('h3', { text: 'Your account' });
        wrap.appendChild(title);

        const userCard = createEl('button', { className: 'sidebar-user-card' });
        userCard.appendChild(renderAvatar(state.user, 48, { eager: true }));
        const userInfo = createEl('div', { className: 'sidebar-user-info' });
        const displayName = state.user ? (state.user.display_name || state.user.username) : 'Guest';
        const username = state.user ? ('@' + state.user.username) : '';
        userInfo.appendChild(createEl('div', { className: 'name', text: displayName }));
        userInfo.appendChild(createEl('div', { className: 'username', text: username }));
        userCard.appendChild(userInfo);
        userCard.addEventListener('click', () => router.navigate('/profile'));
        wrap.appendChild(userCard);

        if (state.isAdmin) {
            const adminLink = createEl('button', { className: 'sidebar-item', style: 'margin-top:8px;' });
            adminLink.innerHTML = shell.icons.settings + '<span>Admin panel</span>';
            adminLink.addEventListener('click', () => window.open('/admin', '_blank'));
            wrap.appendChild(adminLink);
        }

        const hint = createEl('p', { className: 'sidebar-hint', text: 'Tip: tap your profile to update your avatar.' });
        wrap.appendChild(hint);
        return wrap;
    },

    updateDesktopSidebars() {
        const left = document.getElementById('sidebar-left');
        if (left) {
            const nav = left.querySelector('.sidebar-menu');
            if (nav) {
                const newNav = this.renderSidebarNav().querySelector('.sidebar-menu');
                nav.replaceWith(newNav);
            }
        }
        const right = document.getElementById('sidebar-right');
        if (right) {
            const content = right.querySelector('.sidebar-right-content');
            if (content) content.replaceWith(this.renderSidebarRight());
        }
    },

    navigateTab(tabId) {
        if (tabId === 'home') router.navigate('/');
        else if (tabId === 'profile') router.navigate('/profile');
        else router.navigate('/' + tabId);
    },

    getActiveTab() {
        const path = router.getPath();
        if (path === '/' || path === '/home') return 'home';
        if (path === '/search') return 'search';
        if (path === '/create') return 'create';
        if (path === '/notifications') return 'notifications';
        if (path.startsWith('/profile')) return 'profile';
        return 'home';
    },

    handleRoute() {
        const path = router.getPath();
        const content = document.getElementById('main-content');
        const tabBar = document.getElementById('tab-bar');
        const leftSidebar = document.getElementById('sidebar-left');
        const rightSidebar = document.getElementById('sidebar-right');
        clearEl(content);

        const hideChrome = path === '/login' || path === '/setup' || path === '/force-password-change';
        if (this.root) this.root.classList.toggle('no-sidebars', hideChrome);
        if (tabBar) tabBar.classList.toggle('hidden', hideChrome);
        if (leftSidebar) leftSidebar.classList.toggle('hidden', hideChrome);
        if (rightSidebar) rightSidebar.classList.toggle('hidden', hideChrome);

        if (path === '/login' || path === '/setup') {
            loginComponent.render(content);
            return;
        }

        if (!state.isAuthenticated) {
            router.navigate('/login');
            return;
        }

        if (state.requiresPasswordChange && path !== '/force-password-change') {
            forcePasswordChangeComponent.render(content);
            return;
        }

        if (path === '/' || path === '/home') {
            homeComponent.render(content);
        } else if (path === '/search') {
            searchComponent.render(content);
        } else if (path === '/create') {
            composerComponent.render(content);
        } else if (path === '/notifications') {
            notificationsComponent.render(content);
        } else if (path === '/profile' || path.startsWith('/profile/')) {
            profileComponent.render(content, router.params.id);
        } else if (path === '/settings') {
            settingsComponent.render(content);
        } else {
            router.navigate('/');
        }
    },

    updateActiveTab() {
        const active = this.getActiveTab();
        const filledIcons = { home: 'homeFill', profile: 'profileFill', notifications: 'bellFill' };

        $$('.tab-item', this.root).forEach(btn => {
            const tabId = btn.getAttribute('data-tab');
            const isActive = tabId === active;
            btn.classList.toggle('active', isActive);
            const iconKey = isActive && filledIcons[tabId] ? filledIcons[tabId] : tabId;
            const label = btn.querySelector('span').textContent;
            btn.innerHTML = this.icons[iconKey] + '<span>' + escapeHtml(label) + '</span>';
        });

        $$('.sidebar-item', this.root).forEach(btn => {
            const tabId = btn.getAttribute('data-tab');
            const isActive = tabId === active;
            btn.classList.toggle('active', isActive);
            const iconKey = isActive && filledIcons[tabId] ? filledIcons[tabId] : tabId;
            const label = btn.querySelector('span').textContent;
            btn.innerHTML = this.icons[iconKey] + '<span>' + escapeHtml(label) + '</span>';
        });
    },

    show() {
        this.render();
    }
};

window.addEventListener('circle:route', () => {
    if (!shell.root) return;
    shell.updateActiveTab();
    shell.updateDesktopSidebars();
    shell.handleRoute();
});
