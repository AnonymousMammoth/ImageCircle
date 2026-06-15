/**
 * Single feed post card with like, comment, caption, and double-tap like.
 */

const postCardComponent = {
    _pendingLikes: new Set(),

    render(post, onChange, onComment) {
        const wrapper = createEl('div', { className: 'post-card', 'data-post-id': post.id });

        wrapper.appendChild(this.renderHeader(post));

        if (isTextOnlyPost(post)) {
            wrapper.appendChild(this.renderTextContent(post));
        } else {
            wrapper.appendChild(this.renderMedia(post));
        }

        wrapper.appendChild(this.renderActions(post, onChange, onComment));
        wrapper.appendChild(this.renderInfo(post, onComment));

        return wrapper;
    },

    renderHeader(post) {
        const header = createEl('div', { className: 'post-header' });
        const avatar = renderAvatar(post.user, 40);
        avatar.style.cursor = 'pointer';
        avatar.addEventListener('click', () => router.navigate('/profile/' + post.user.id));

        const meta = createEl('div', { className: 'meta' });
        const displayName = createEl('div', { className: 'display-name', text: usernameDisplay(post.user) });
        displayName.style.cursor = 'pointer';
        displayName.addEventListener('click', () => router.navigate('/profile/' + post.user.id));
        const username = createEl('div', { className: 'username', text: '@' + post.user.username });
        username.style.cursor = 'pointer';
        username.addEventListener('click', () => router.navigate('/profile/' + post.user.id));
        meta.appendChild(displayName);
        meta.appendChild(username);

        const time = createEl('span', { className: 'time', text: relativeTime(post.created_at) });

        header.appendChild(avatar);
        header.appendChild(meta);
        header.appendChild(time);

        if (canManageContent(post.user.id, state.user)) {
            const menuBtn = createEl('button', { className: 'menu-btn' });
            menuBtn.innerHTML = shell.icons.menu;
            menuBtn.addEventListener('click', () => this.deletePost(post));
            header.appendChild(menuBtn);
        }

        return header;
    },

    renderMedia(post) {
        const url = postMediaUrl(post);
        const wrap = createEl('div', { style: 'position:relative;' });
        const img = createEl('img', { className: 'post-media', src: url, alt: '', loading: 'lazy' });
        img.onerror = function() { this.style.display = 'none'; };

        let lastTap = 0;
        img.addEventListener('click', () => {
            const now = Date.now();
            if (now - lastTap < 300) {
                this.toggleLike(post);
                this.animateHeart(wrap);
            }
            lastTap = now;
        });

        wrap.appendChild(img);
        return wrap;
    },

    renderTextContent(post) {
        const wrap = createEl('div', { className: 'post-text-content' });
        const text = createEl('p');
        text.textContent = post.caption || 'Text post';

        let lastTap = 0;
        wrap.addEventListener('click', () => {
            const now = Date.now();
            if (now - lastTap < 300) this.toggleLike(post);
            lastTap = now;
        });

        wrap.appendChild(text);
        return wrap;
    },

    renderActions(post, onChange, onComment) {
        const actions = createEl('div', { className: 'post-actions' });

        const likeBtn = createEl('button', { className: post.has_liked ? 'liked' : '' });
        likeBtn.innerHTML = post.has_liked ? shell.icons.heartFill : shell.icons.heart;
        likeBtn.addEventListener('click', () => this.toggleLike(post));

        const commentBtn = createEl('button');
        commentBtn.innerHTML = shell.icons.comment;
        commentBtn.addEventListener('click', () => onComment(post));

        actions.appendChild(likeBtn);
        actions.appendChild(commentBtn);
        return actions;
    },

    renderInfo(post, onComment) {
        const info = createEl('div', { className: 'post-info' });
        const likes = createEl('div', { className: 'likes', text: post.likes_count + ' likes' });
        info.appendChild(likes);

        if (!isTextOnlyPost(post) && post.caption) {
            const caption = createEl('div', { className: 'caption' });
            caption.appendChild(createEl('span', { className: 'author', text: post.user.username }));
            caption.appendChild(document.createTextNode(post.caption));
            info.appendChild(caption);
        }

        if (post.comments_count > 0) {
            const commentsBtn = createEl('button', { className: 'comments-btn' });
            commentsBtn.textContent = 'View all ' + post.comments_count + ' comments';
            commentsBtn.addEventListener('click', () => onComment(post));
            info.appendChild(commentsBtn);
        }

        return info;
    },

    async toggleLike(post) {
        if (this._pendingLikes.has(post.id)) return;
        this._pendingLikes.add(post.id);

        const card = document.querySelector('.post-card[data-post-id="' + post.id + '"]');
        if (!card) {
            this._pendingLikes.delete(post.id);
            return;
        }

        const previousHasLiked = post.has_liked;
        const previousCount = post.likes_count;

        // Optimistic update
        post.has_liked = !post.has_liked;
        post.likes_count += post.has_liked ? 1 : -1;
        this.updateCardState(card, post);

        try {
            const result = await toggleLike(post.id);
            post.has_liked = result.liked;
            post.likes_count = result.like_count;
            this.updateCardState(card, post);
        } catch (err) {
            // Revert
            post.has_liked = previousHasLiked;
            post.likes_count = previousCount;
            this.updateCardState(card, post);
        } finally {
            this._pendingLikes.delete(post.id);
        }
    },

    updateCardState(card, post) {
        const likeBtn = card.querySelector('.post-actions button');
        if (likeBtn) {
            likeBtn.className = post.has_liked ? 'liked' : '';
            likeBtn.innerHTML = post.has_liked ? shell.icons.heartFill : shell.icons.heart;
        }
        const likes = card.querySelector('.post-info .likes');
        if (likes) likes.textContent = post.likes_count + ' likes';
    },

    animateHeart(container) {
        const heart = createEl('div', { className: 'heart-overlay' });
        heart.innerHTML = shell.icons.heartFill;
        heart.style.width = '100px';
        heart.style.height = '100px';
        document.body.appendChild(heart);

        requestAnimationFrame(() => {
            heart.classList.add('show');
        });

        setTimeout(() => {
            heart.remove();
        }, 600);
    },

    async deletePost(post) {
        if (!confirmAction('Delete this post? This cannot be undone.')) return;
        try {
            await deletePost(post.id);
            const card = document.querySelector('.post-card[data-post-id="' + post.id + '"]');
            if (card) card.remove();
        } catch (err) {
            showAlert(err.message);
        }
    }
};
