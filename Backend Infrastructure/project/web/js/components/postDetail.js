/**
 * Post detail screen reached from notifications or deep links.
 */

const postDetailComponent = {
    postId: null,
    mountToken: null,

    render(container, postId) {
        if (this.mountToken) this.mountToken.cancel();
        this.mountToken = createMountToken();
        const token = this.mountToken;
        this.postId = postId;

        clearEl(container);
        container.className = 'screen-scroll tab-content';

        const header = createEl('div', { className: 'top-header' });
        const left = createEl('div', { className: 'header-left' });
        const backBtn = createEl('button', { className: 'btn-icon' });
        backBtn.innerHTML = shell.icons.close;
        backBtn.addEventListener('click', () => router.back());
        left.appendChild(backBtn);
        header.appendChild(left);
        header.appendChild(createEl('h1', { text: 'Post' }));
        container.appendChild(header);

        const body = createEl('div', { id: 'post-detail-body', className: 'post-detail-body' });
        body.appendChild(createEl('div', { className: 'loading-center' }, [createEl('div', { className: 'spinner' })]));
        container.appendChild(body);

        this.loadPost(token);
    },

    async loadPost(token) {
        const body = document.getElementById('post-detail-body');
        if (!body) return;
        try {
            const post = await fetchPost(this.postId);
            if (!token.isActive()) return;
            clearEl(body);
            const card = postCardComponent.render(
                post,
                () => this.loadPost(token),
                (p) => commentsComponent.open(p)
            );
            body.appendChild(card);
        } catch (err) {
            if (!token.isActive()) return;
            clearEl(body);
            body.appendChild(createEl('p', {
                className: 'error-text',
                style: 'text-align:center;padding:40px;',
                text: err.message || 'Could not load post.'
            }));
        }
    }
};
