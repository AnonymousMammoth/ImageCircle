/**
 * Profile screen for current user or another user.
 */

const profileComponent = {
    user: null,
    posts: [],
    filter: 'mixed',
    hasLoaded: false,
    cachedUserId: null,
    mountToken: null,
    userNotFound: false,

    async render(container, userId) {
        if (this.mountToken) this.mountToken.cancel();
        this.mountToken = createMountToken();
        const token = this.mountToken;

        clearEl(container);
        container.className = 'screen-scroll tab-content';
        this.userNotFound = false;

        const isCurrentUser = !userId || (state.user && String(state.user.id) === String(userId));
        const cacheKey = isCurrentUser ? (state.user ? state.user.id : null) : userId;

        if (this.hasLoaded && String(this.cachedUserId) === String(cacheKey) && !this.userNotFound) {
            if (isCurrentUser) this.user = state.user;
            this.renderHeader(container, isCurrentUser);
            this.renderFilter(container);
            this.renderGrid(container);
            return;
        }

        if (!isCurrentUser) {
            try {
                this.posts = await fetchUserPosts(userId);
                if (!token.isActive()) return;
                if (this.posts.length > 0) {
                    this.user = this.posts[0].user;
                } else {
                    this.userNotFound = true;
                }
            } catch (err) {
                if (!token.isActive()) return;
                this.userNotFound = true;
                this.posts = [];
            }
        } else {
            this.user = state.user;
            try {
                this.posts = await fetchUserPosts(state.user.id);
            } catch (err) {
                if (!token.isActive()) return;
                showAlert(err.message);
                this.posts = [];
            }
        }

        if (!token.isActive()) return;
        this.cachedUserId = cacheKey;
        this.hasLoaded = true;

        if (this.userNotFound) {
            this.renderNotFound(container);
            return;
        }

        this.renderHeader(container, isCurrentUser);
        this.renderFilter(container);
        this.renderGrid(container);
    },

    renderNotFound(container) {
        const wrap = createEl('div', { className: 'empty-state', style: 'padding-top:40px;' });
        wrap.innerHTML = shell.icons.warning;
        const title = createEl('h3', { text: 'User not found' });
        const desc = createEl('p', { text: 'The profile you are looking for does not exist.' });
        wrap.appendChild(title);
        wrap.appendChild(desc);
        container.appendChild(wrap);
    },

    renderHeader(container, isCurrentUser) {
        const header = createEl('div', { className: 'profile-header' });

        const avatarWrap = createEl('div', { className: 'profile-avatar-upload' });
        avatarWrap.appendChild(renderAvatar(this.user, 80));
        if (isCurrentUser) {
            const badge = createEl('div', { className: 'upload-badge' });
            badge.innerHTML = shell.icons.camera;
            const fileInput = createEl('input', { type: 'file', accept: 'image/*' });
            fileInput.addEventListener('change', (e) => this.uploadAvatar(e.target.files[0]));
            avatarWrap.appendChild(badge);
            avatarWrap.appendChild(fileInput);
        }

        const username = createEl('div', { className: 'username', text: this.user.username });
        const displayName = createEl('div', { className: 'display-name', text: this.user.display_name || '' });

        header.appendChild(avatarWrap);
        header.appendChild(username);
        header.appendChild(displayName);
        container.appendChild(header);

        const stats = createEl('div', { className: 'profile-stats' });
        const stat = createEl('div', { className: 'stat' });
        stat.appendChild(createEl('div', { className: 'stat-value', text: String(this.filteredPosts().length) }));
        stat.appendChild(createEl('div', { className: 'stat-label', text: 'posts' }));
        stats.appendChild(stat);
        container.appendChild(stats);

        if (isCurrentUser) {
            const settingsBtn = createEl('button', {
                className: 'btn btn-secondary',
                style: 'margin:0 16px 16px;'
            });
            settingsBtn.innerHTML = shell.icons.settings + ' Settings';
            settingsBtn.addEventListener('click', () => router.navigate('/settings'));
            container.appendChild(settingsBtn);
        }
    },

    renderFilter(container) {
        const wrap = createEl('div', { className: 'profile-filter' });
        const control = createEl('div', { className: 'segmented-control' });
        const options = [
            { key: 'mixed', label: 'Mixed' },
            { key: 'images', label: 'Images' },
            { key: 'text', label: 'Text' }
        ];
        options.forEach(opt => {
            const btn = createEl('button', { type: 'button', className: opt.key === this.filter ? 'active' : '' });
            btn.textContent = opt.label;
            btn.addEventListener('click', () => {
                this.filter = opt.key;
                const grid = document.getElementById('profile-grid');
                if (grid) this.renderGridContent(grid);
                Array.from(control.children).forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
            });
            control.appendChild(btn);
        });
        wrap.appendChild(control);
        container.appendChild(wrap);
    },

    filteredPosts() {
        return this.posts.filter(post => {
            if (this.filter === 'mixed') return true;
            if (this.filter === 'images') return !isTextOnlyPost(post);
            return isTextOnlyPost(post);
        });
    },

    renderGrid(container) {
        const grid = createEl('div', { id: 'profile-grid', className: this.filter === 'text' ? '' : 'profile-grid' });
        this.renderGridContent(grid);
        container.appendChild(grid);
    },

    renderGridContent(grid) {
        clearEl(grid);
        grid.className = this.filter === 'text' ? '' : 'profile-grid';
        const filtered = this.filteredPosts();

        if (filtered.length === 0) {
            grid.appendChild(createEl('div', { className: 'empty-state' }, [
                createEl('p', { text: 'No posts yet.' })
            ]));
            return;
        }

        if (this.filter === 'text') {
            filtered.forEach(post => {
                const card = postCardComponent.render(post, () => this.refresh(), (p) => commentsComponent.open(p));
                grid.appendChild(card);
            });
        } else {
            filtered.forEach(post => {
                const cell = createEl('button', { className: 'profile-grid-cell' });
                if (isTextOnlyPost(post)) {
                    const textCell = createEl('div', { className: 'text-cell' });
                    textCell.innerHTML = shell.icons.quote;
                    const caption = createEl('p', { text: post.caption || 'Text post' });
                    textCell.appendChild(caption);
                    cell.appendChild(textCell);
                } else {
                    const thumbUrl = postThumbnailUrl(post);
                    const img = createEl('img', { src: thumbUrl, alt: '', loading: 'lazy' });
                    img.onerror = function() { this.style.display = 'none'; };
                    cell.appendChild(img);
                }
                cell.addEventListener('click', () => this.showPostDetail(post));
                grid.appendChild(cell);
            });
        }
    },

    showPostDetail(post) {
        const overlay = createEl('div', { className: 'modal-overlay' });
        overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.remove(); });

        const sheet = createEl('div', { className: 'modal-sheet' });
        const header = createEl('div', { className: 'modal-sheet-header' });
        header.appendChild(createEl('h2', { text: 'Post' }));
        const closeBtn = createEl('button', { className: 'btn-icon' });
        closeBtn.innerHTML = shell.icons.close;
        closeBtn.addEventListener('click', () => overlay.remove());
        header.appendChild(closeBtn);

        const body = createEl('div', { className: 'modal-sheet-body' });
        const detail = createEl('div', { className: 'post-detail' });

        if (isTextOnlyPost(post)) {
            const text = createEl('div', { className: 'post-detail-text' });
            text.appendChild(createEl('p', { text: post.caption || 'Text post' }));
            detail.appendChild(text);
        } else {
            const url = postMediaUrl(post);
            detail.appendChild(createEl('img', { className: 'post-detail-media', src: url, alt: '' }));
            if (post.caption) {
                detail.appendChild(createEl('p', { text: post.caption }));
            }
        }

        const counts = createEl('div', { style: 'display:flex;gap:16px;color:var(--text-secondary);' });
        counts.appendChild(createEl('span', { text: post.likes_count + ' likes' }));
        counts.appendChild(createEl('span', { text: post.comments_count + ' comments' }));
        detail.appendChild(counts);

        if (canManageContent(post.user.id, state.user)) {
            const delBtn = createEl('button', { className: 'btn btn-danger', style: 'margin-top:16px;width:100%;' });
            delBtn.innerHTML = shell.icons.trash + ' Delete Post';
            delBtn.addEventListener('click', () => this.deletePost(post, overlay));
            detail.appendChild(delBtn);
        }

        body.appendChild(detail);
        sheet.appendChild(header);
        sheet.appendChild(body);
        overlay.appendChild(sheet);
        document.body.appendChild(overlay);
    },

    async deletePost(post, overlay) {
        if (!confirmAction('Delete this post? This cannot be undone.')) return;
        try {
            await deletePost(post.id);
            overlay.remove();
            this.refresh();
        } catch (err) {
            showAlert(err.message);
        }
    },

    async uploadAvatar(file) {
        if (!file) return;
        try {
            const data = await uploadAvatar(file);
            state.updateUser(data);
            this.user = data;
            this.refresh();
        } catch (err) {
            showAlert(err.message);
        }
    },

    async refresh() {
        this.hasLoaded = false;
        this.cachedUserId = null;
        this.userNotFound = false;
        const container = document.getElementById('main-content');
        if (!this.user) {
            if (container) this.render(container, null);
            return;
        }
        const userId = state.user && String(this.user.id) === String(state.user.id) ? null : this.user.id;
        if (container) this.render(container, userId);
    }
};
