/**
 * Notifications screen listing likes and comments.
 */

const notificationsComponent = {
    notifications: [],
    isLoading: false,
    hasLoaded: false,
    mountToken: null,

    render(container) {
        if (this.mountToken) this.mountToken.cancel();
        this.mountToken = createMountToken();
        const token = this.mountToken;

        clearEl(container);
        container.className = 'screen-scroll tab-content';

        const header = createEl('div', { className: 'top-header' });
        header.appendChild(createEl('h1', { text: 'Notifications' }));
        container.appendChild(header);

        const list = createEl('div', { id: 'notifications-list', className: 'notifications-list' });
        container.appendChild(list);

        this.renderList(list);
        if (!this.hasLoaded) {
            this.loadData(token);
        }
    },

    renderList(list) {
        clearEl(list);
        if (this.isLoading && this.notifications.length === 0) {
            list.appendChild(createEl('div', { className: 'loading-center' }, [createEl('div', { className: 'spinner' })]));
            return;
        }
        if (this.notifications.length === 0) {
            list.appendChild(createEl('div', { className: 'empty-state' }, [
                createEl('p', { text: 'No notifications yet.' })
            ]));
            return;
        }
        this.notifications.forEach(n => list.appendChild(this.renderItem(n)));
    },

    renderItem(notification) {
        const item = createEl('button', { className: 'notification-item' });
        const actor = notification.actor || {};
        const post = notification.post || {};
        const comment = notification.comment || {};

        item.appendChild(renderAvatar(actor, 44));

        const body = createEl('div', { className: 'notification-body' });
        const text = createEl('div', { className: 'notification-text' });
        const actorName = createEl('span', { className: 'author', text: usernameDisplay(actor) });
        text.appendChild(actorName);
        const type = notification.type || '';
        if (type === 'like') {
            text.appendChild(document.createTextNode(' liked your post.'));
        } else if (type === 'comment') {
            text.appendChild(document.createTextNode(' commented: '));
            const commentText = createEl('span', { className: 'notification-comment', text: comment.text || '' });
            text.appendChild(commentText);
        } else if (type === 'mention_post') {
            const preview = post && post.caption ? post.caption : 'a post';
            text.appendChild(document.createTextNode(' mentioned you in a post: '));
            const postPreview = createEl('span', { className: 'notification-comment', text: preview });
            text.appendChild(postPreview);
        } else if (type === 'mention_comment') {
            const preview = comment && comment.text ? comment.text : 'a comment';
            text.appendChild(document.createTextNode(' mentioned you in a comment: '));
            const commentPreview = createEl('span', { className: 'notification-comment', text: preview });
            text.appendChild(commentPreview);
        } else {
            text.appendChild(document.createTextNode(' interacted with your post.'));
        }
        body.appendChild(text);
        body.appendChild(createEl('div', { className: 'time', text: relativeTime(notification.created_at) }));
        item.appendChild(body);

        if (post && post.id) {
            const thumb = createEl('div', { className: 'notification-thumb' });
            if (!isTextOnlyPost(post)) {
                const url = postThumbnailUrl(post);
                const img = createEl('img', { src: url, alt: '', loading: 'lazy' });
                img.onerror = function() { this.style.display = 'none'; };
                thumb.appendChild(img);
            } else {
                thumb.innerHTML = shell.icons.quote;
                thumb.classList.add('text');
            }
            item.appendChild(thumb);
        }

        item.addEventListener('click', () => {
            const targetUserId = (post && post.user_id) || actor.id;
            if (targetUserId) router.navigate('/profile/' + targetUserId);
        });

        return item;
    },

    async loadData(token) {
        this.isLoading = true;
        const list = document.getElementById('notifications-list');
        if (list) this.renderList(list);

        try {
            const data = await fetchNotifications();
            if (!token.isActive()) return;
            this.notifications = data;
            this.hasLoaded = true;
        } catch (err) {
            if (!token.isActive()) return;
            console.error(err);
        } finally {
            this.isLoading = false;
            if (token.isActive()) {
                const list2 = document.getElementById('notifications-list');
                if (list2) this.renderList(list2);
            }
        }
    }
};
