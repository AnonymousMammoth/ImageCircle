/**
 * Debounced user search screen.
 */

const searchComponent = {
    results: [],
    isSearching: false,

    render(container) {
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

        const doSearch = debounce((query) => this.search(query), 300);
        input.addEventListener('input', (e) => {
            const query = e.target.value.trim();
            if (!query) {
                this.results = [];
                this.renderResults(results);
                return;
            }
            doSearch(query);
        });

        input.focus();
    },

    async search(query) {
        this.isSearching = true;
        const results = document.getElementById('search-results');
        if (results) this.renderResults(results);
        try {
            this.results = await searchUsers(query);
        } catch (err) {
            this.results = [];
        } finally {
            this.isSearching = false;
            if (results) this.renderResults(results);
        }
    },

    renderResults(container) {
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
