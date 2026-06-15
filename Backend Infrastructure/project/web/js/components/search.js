/**
 * Debounced user search screen.
 */

const searchComponent = {
    results: [],
    query: '',
    loadedQuery: '',
    isSearching: false,
    mountToken: null,

    render(container) {
        if (this.mountToken) this.mountToken.cancel();
        this.mountToken = createMountToken();
        const token = this.mountToken;

        clearEl(container);
        container.className = 'screen-scroll tab-content';

        const searchBar = createEl('div', { className: 'search-bar' });
        const input = createEl('input', {
            type: 'text',
            id: 'search-input',
            placeholder: 'Search by username',
            autocomplete: 'off'
        });
        searchBar.appendChild(input);
        container.appendChild(searchBar);

        const results = createEl('div', { id: 'search-results', className: 'search-results' });
        container.appendChild(results);

        const doSearch = debounce((q) => this.search(q, token), 300);
        input.addEventListener('input', (e) => {
            this.query = e.target.value.trim();
            if (!this.query) {
                this.results = [];
                this.loadedQuery = '';
                this.renderResults(results, token);
                return;
            }
            doSearch(this.query);
        });

        if (this.query) {
            input.value = this.query;
            if (this.loadedQuery === this.query && this.results.length > 0) {
                this.renderResults(results, token);
            } else {
                doSearch(this.query);
            }
        }

        input.focus();
    },

    async search(query, token) {
        this.isSearching = true;
        this.query = query;
        const results = document.getElementById('search-results');
        if (results) this.renderResults(results, token);
        try {
            this.results = await searchUsers(query);
            this.loadedQuery = query;
        } catch (err) {
            this.results = [];
            this.loadedQuery = '';
        } finally {
            this.isSearching = false;
            if (token && token.isActive()) {
                const results = document.getElementById('search-results');
                if (results) this.renderResults(results, token);
            }
        }
    },

    renderResults(container, token) {
        if (token && !token.isActive()) return;
        clearEl(container);
        if (this.isSearching) {
            container.appendChild(createEl('div', { className: 'loading-center' }, [createEl('div', { className: 'spinner' })]));
            return;
        }
        if (this.results.length === 0) {
            container.appendChild(createEl('div', { className: 'empty-state' }, [
                createEl('p', { text: 'No users found.' })
            ]));
            return;
        }
        this.results.forEach(user => {
            const btn = createEl('button', { className: 'search-result' });
            btn.appendChild(renderAvatar(user, 40));
            const info = createEl('div', { className: 'info' });
            info.appendChild(createEl('div', { className: 'name', text: user.username }));
            info.appendChild(createEl('div', { className: 'display', text: user.display_name || '' }));
            btn.appendChild(info);
            btn.addEventListener('click', () => router.navigate('/profile/' + user.id));
            container.appendChild(btn);
        });
    }
};
