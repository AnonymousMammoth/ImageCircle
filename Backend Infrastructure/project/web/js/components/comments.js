/**
 * Comments modal sheet.
 */

const commentsComponent = {
    post: null,

    open(post) {
        this.post = post;
        this.render();
        this.loadComments();
    },

    render() {
        const existing = document.getElementById('comments-sheet');
        if (existing) existing.remove();

        const overlay = createEl('div', { id: 'comments-sheet', className: 'modal-overlay' });
        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) this.close();
        });

        const sheet = createEl('div', { className: 'modal-sheet', style: 'height:70vh;' });
        const header = createEl('div', { className: 'modal-sheet-header' });
        const title = createEl('h2', { text: 'Comments' });
        const closeBtn = createEl('button', { className: 'btn-icon' });
        closeBtn.innerHTML = shell.icons.close;
        closeBtn.addEventListener('click', () => this.close());
        header.appendChild(title);
        header.appendChild(closeBtn);

        const body = createEl('div', { className: 'modal-sheet-body' });
        const list = createEl('div', { id: 'comments-list', className: 'comments-list' });
        body.appendChild(list);

        const inputRow = createEl('div', { className: 'comment-input-row' });
        const input = createEl('input', {
            type: 'text',
            id: 'comment-input',
            placeholder: 'Add a comment...'
        });
        const sendBtn = createEl('button');
        sendBtn.innerHTML = shell.icons.send;
        sendBtn.disabled = true;

        const submit = () => {
            const text = input.value.trim();
            if (!text) return;
            this.submitComment(text, input, sendBtn);
        };

        input.addEventListener('input', () => {
            sendBtn.disabled = input.value.trim() === '';
        });
        input.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') submit();
        });
        sendBtn.addEventListener('click', submit);

        inputRow.appendChild(input);
        inputRow.appendChild(sendBtn);

        sheet.appendChild(header);
        sheet.appendChild(body);
        sheet.appendChild(inputRow);
        overlay.appendChild(sheet);
        document.body.appendChild(overlay);

        input.focus();
    },

    close() {
        const sheet = document.getElementById('comments-sheet');
        if (sheet) sheet.remove();
        this.post = null;
    },

    async loadComments() {
        const list = document.getElementById('comments-list');
        if (!list) return;
        clearEl(list);
        list.appendChild(createEl('div', { className: 'loading-center' }, [createEl('div', { className: 'spinner' })]));

        try {
            const comments = await fetchComments(this.post.id);
            clearEl(list);
            if (comments.length === 0) {
                list.appendChild(createEl('p', {
                    className: 'empty-state',
                    style: 'padding:40px 0;',
                    text: 'No comments yet.'
                }));
                return;
            }
            comments.forEach(comment => {
                list.appendChild(this.renderComment(comment));
            });
        } catch (err) {
            clearEl(list);
            list.appendChild(createEl('p', { className: 'error-text', style: 'text-align:center;padding:20px;', text: err.message }));
        }
    },

    renderComment(comment) {
        const el = createEl('div', { className: 'comment' });
        const avatar = renderAvatar(comment.user, 32);
        avatar.style.cursor = 'pointer';
        avatar.addEventListener('click', () => {
            this.close();
            router.navigate('/profile/' + comment.user.id);
        });

        const body = createEl('div', { className: 'body' });
        const textRow = createEl('div');
        const author = createEl('span', { className: 'author', text: comment.user.username });
        author.style.cursor = 'pointer';
        author.addEventListener('click', () => {
            this.close();
            router.navigate('/profile/' + comment.user.id);
        });
        textRow.appendChild(author);
        textRow.appendChild(createEl('span', { className: 'text', text: comment.text }));
        const time = createEl('div', { className: 'time', text: relativeTime(comment.created_at) });

        body.appendChild(textRow);
        body.appendChild(time);

        el.appendChild(avatar);
        el.appendChild(body);

        if (isOwnContent(comment.user.id, state.user)) {
            const delBtn = createEl('button', { className: 'btn-icon btn-small', style: 'width:32px;height:32px;' });
            delBtn.innerHTML = shell.icons.trash;
            delBtn.addEventListener('click', () => this.deleteComment(comment));
            el.appendChild(delBtn);
        }

        return el;
    },

    async submitComment(text, input, sendBtn) {
        sendBtn.disabled = true;
        input.disabled = true;
        try {
            await createComment(this.post.id, text);
            input.value = '';
            this.loadComments();
            this.post.comments_count = (this.post.comments_count || 0) + 1;
        } catch (err) {
            showAlert(err.message);
        } finally {
            input.disabled = false;
            sendBtn.disabled = input.value.trim() === '';
            input.focus();
        }
    },

    async deleteComment(comment) {
        if (!confirmAction('Delete this comment?')) return;
        try {
            await deleteComment(comment.id);
            this.loadComments();
            this.post.comments_count = Math.max((this.post.comments_count || 0) - 1, 0);
        } catch (err) {
            showAlert(err.message);
        }
    }
};
