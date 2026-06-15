/**
 * Home feed screen with stories tray, posts, and feed filter.
 */

const homeComponent = {
    posts: [],
    storyGroups: [],
    filter: 'mixed',
    isLoading: false,

    render(container) {
        clearEl(container);
        container.className = 'screen-scroll tab-content';

        const storiesTray = storiesTrayComponent.render({
            groups: this.storyGroups,
            onAddStory: () => router.navigate('/create'),
            onSelectGroup: (groupIndex) => {
                storyViewerComponent.open(this.storyGroups, groupIndex);
            }
        });
        container.appendChild(storiesTray);

        const filterEl = createEl('div', { className: 'feed-filter' });
        filterEl.appendChild(this.renderFilter());
        container.appendChild(filterEl);

        const feedContainer = createEl('div', { id: 'feed-container' });
        container.appendChild(feedContainer);

        this.renderFeed(feedContainer);

        // Pull to refresh via simple reload button / swipe down gesture
        let startY = 0;
        container.addEventListener('touchstart', (e) => { startY = e.touches[0].clientY; }, { passive: true });
        container.addEventListener('touchend', (e) => {
            const endY = e.changedTouches[0].clientY;
            if (endY - startY > 120 && container.scrollTop <= 0) {
                this.loadData();
            }
        }, { passive: true });

        this.loadData();
    },

    renderFilter() {
        const wrap = createEl('div', { className: 'segmented-control' });
        const options = [
            { key: 'mixed', label: 'Mixed' },
            { key: 'images', label: 'Images' },
            { key: 'text', label: 'Text' }
        ];
        options.forEach(opt => {
            const btn = createEl('button', {
                type: 'button',
                className: opt.key === this.filter ? 'active' : ''
            });
            btn.textContent = opt.label;
            btn.addEventListener('click', () => {
                this.filter = opt.key;
                const feed = document.getElementById('feed-container');
                if (feed) this.renderFeed(feed);
                // update active state
                Array.from(wrap.children).forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
            });
            wrap.appendChild(btn);
        });
        return wrap;
    },

    filteredPosts() {
        return this.posts.filter(post => {
            if (this.filter === 'mixed') return true;
            if (this.filter === 'images') return !isTextOnlyPost(post);
            return isTextOnlyPost(post);
        });
    },

    renderFeed(container) {
        clearEl(container);

        if (this.isLoading && this.posts.length === 0) {
            container.appendChild(createEl('div', { className: 'loading-center' }, [createEl('div', { className: 'spinner' })]));
            return;
        }

        const filtered = this.filteredPosts();
        if (filtered.length === 0) {
            container.appendChild(this.emptyState());
            return;
        }

        filtered.forEach(post => {
            const card = postCardComponent.render(post, () => this.loadData(), (p) => commentsComponent.open(p));
            container.appendChild(card);
        });
    },

    emptyState() {
        const state = createEl('div', { className: 'empty-state' });
        const iconKey = this.filter === 'text' ? 'text' : 'image';
        state.innerHTML = shell.icons[iconKey];
        const title = createEl('h3');
        if (this.filter === 'mixed') title.textContent = 'No posts yet';
        else if (this.filter === 'images') title.textContent = 'No image posts yet';
        else title.textContent = 'No text posts yet';
        state.appendChild(title);
        const p = createEl('p');
        p.textContent = this.filter === 'mixed' ? 'Be the first to share!' : '';
        state.appendChild(p);
        return state;
    },

    async loadData() {
        this.isLoading = true;
        const feed = document.getElementById('feed-container');
        if (feed) this.renderFeed(feed);

        try {
            const [posts, stories] = await Promise.all([
                fetchFeed(),
                fetchStories()
            ]);
            this.posts = posts;

            let allStories = stories;
            if (state.user && state.user.id) {
                try {
                    const mine = await fetchUserStories(state.user.id);
                    const others = stories.filter(s => String(s.user.id) !== String(state.user.id));
                    allStories = mine.concat(others);
                } catch (_) {}
            }

            this.storyGroups = groupStoriesByUser(allStories);
            // Move own group to front
            if (state.user) {
                const ownIndex = this.storyGroups.findIndex(g => String(g.user.id) === String(state.user.id));
                if (ownIndex > 0) {
                    const own = this.storyGroups.splice(ownIndex, 1)[0];
                    this.storyGroups.unshift(own);
                }
            }
        } catch (err) {
            // Stories failure is non-fatal
            console.error(err);
        } finally {
            this.isLoading = false;
            const tray = document.querySelector('.stories-tray');
            if (tray) {
                const newTray = storiesTrayComponent.render({
                    groups: this.storyGroups,
                    onAddStory: () => router.navigate('/create'),
                    onSelectGroup: (groupIndex) => {
                        storyViewerComponent.open(this.storyGroups, groupIndex);
                    }
                });
                tray.replaceWith(newTray);
            }
            const feed2 = document.getElementById('feed-container');
            if (feed2) this.renderFeed(feed2);
        }
    }
};
