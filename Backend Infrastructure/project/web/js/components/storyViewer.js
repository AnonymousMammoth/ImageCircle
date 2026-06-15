/**
 * Full-screen story viewer with progress bars, tap navigation, long-press pause,
 * swipe down to close, auto-advance, video playback, and delete story.
 */

const storyViewerComponent = {
    groups: [],
    groupIndex: 0,
    storyIndex: 0,
    isPaused: false,
    progress: 0,
    timer: null,
    viewedIds: new Set(),
    dragOffset: 0,
    isDragging: false,
    startY: 0,
    currentMedia: null,
    isDeleting: false,

    open(groups, groupIndex) {
        if (!groups || !groups.length) return;
        this.groups = groups;
        this.groupIndex = clamp(groupIndex || 0, 0, groups.length - 1);
        this.storyIndex = 0;
        this.progress = 0;
        this.viewedIds = new Set();
        this.isDeleting = false;
        this.render();
        this.setupStory();
    },

    render() {
        let overlay = document.getElementById('story-viewer-overlay');
        if (overlay) overlay.remove();

        overlay = createEl('div', { id: 'story-viewer-overlay', className: 'fullscreen-overlay' });
        overlay.innerHTML = '<div id="story-content" class="fullscreen-content"></div>';
        document.body.appendChild(overlay);

        const content = document.getElementById('story-content');

        // Progress bars
        const progressWrap = createEl('div', { className: 'story-progress', id: 'story-progress' });
        content.appendChild(progressWrap);

        // Top bar
        const topBar = createEl('div', { className: 'story-top-bar' });
        const userInfo = createEl('div', { className: 'user-info' });
        const current = this.currentStory();
        if (current) {
            userInfo.appendChild(renderAvatar(current.user, 36));
            userInfo.appendChild(createEl('span', { className: 'username', text: current.user.username }));
        }
        topBar.appendChild(userInfo);

        const right = createEl('div', { className: 'story-top-bar-right' });
        const closeBtn = createEl('button', { className: 'story-close-btn' });
        closeBtn.innerHTML = shell.icons.close;
        closeBtn.addEventListener('click', () => this.close());
        right.appendChild(closeBtn);

        if (current && canManageContent(current.user.id, state.user)) {
            const menuBtn = createEl('button', { className: 'story-menu-btn' });
            menuBtn.innerHTML = shell.icons.menu;
            menuBtn.addEventListener('click', (e) => {
                stopEvent(e);
                this.deleteCurrent();
            });
            right.appendChild(menuBtn);
        }
        topBar.appendChild(right);
        content.appendChild(topBar);

        // Tap zones
        const tapZones = createEl('div', { className: 'story-tap-zones' });
        const leftZone = createEl('div', { className: 'story-tap-left' });
        const rightZone = createEl('div', { className: 'story-tap-right' });

        let longPressTimer = null;
        const startLongPress = () => {
            longPressTimer = setTimeout(() => { this.isPaused = true; this.updatePause(); }, 300);
        };
        const endLongPress = () => {
            if (longPressTimer) clearTimeout(longPressTimer);
            if (this.isPaused) {
                this.isPaused = false;
                this.updatePause();
            }
        };

        const addTouch = (el, action) => {
            let isPointerDown = false;
            el.addEventListener('touchstart', (e) => {
                this.isDragging = false;
                this.startY = e.touches[0].clientY;
                startLongPress();
            }, { passive: true });
            el.addEventListener('touchmove', (e) => {
                const y = e.touches[0].clientY;
                const diff = y - this.startY;
                if (diff > 10) {
                    if (longPressTimer) clearTimeout(longPressTimer);
                    this.isPaused = true;
                    this.updatePause();
                    this.isDragging = true;
                    this.dragOffset = diff;
                    overlay.style.transform = 'translateY(' + diff + 'px)';
                    overlay.style.opacity = String(1 - Math.min(diff / 400, 1));
                }
            }, { passive: true });
            el.addEventListener('touchend', (e) => {
                endLongPress();
                if (this.isDragging) {
                    if (this.dragOffset > 120) {
                        this.close();
                    } else {
                        overlay.style.transform = 'translateY(0)';
                        overlay.style.opacity = '1';
                    }
                    this.isDragging = false;
                    this.dragOffset = 0;
                } else {
                    action();
                }
            });

            // Mouse/pointer support for desktop
            el.addEventListener('pointerdown', (e) => {
                isPointerDown = true;
                this.isDragging = false;
                this.startY = e.clientY;
                startLongPress();
            });
            el.addEventListener('pointermove', (e) => {
                if (!isPointerDown) return;
                const diff = e.clientY - this.startY;
                if (diff > 10) {
                    if (longPressTimer) clearTimeout(longPressTimer);
                    this.isPaused = true;
                    this.updatePause();
                    this.isDragging = true;
                    this.dragOffset = diff;
                    overlay.style.transform = 'translateY(' + diff + 'px)';
                    overlay.style.opacity = String(1 - Math.min(diff / 400, 1));
                }
            });
            el.addEventListener('pointerup', (e) => {
                if (!isPointerDown) return;
                isPointerDown = false;
                endLongPress();
                if (this.isDragging) {
                    if (this.dragOffset > 120) {
                        this.close();
                    } else {
                        overlay.style.transform = 'translateY(0)';
                        overlay.style.opacity = '1';
                    }
                    this.isDragging = false;
                    this.dragOffset = 0;
                } else {
                    action();
                }
            });
            el.addEventListener('pointerleave', () => {
                if (!isPointerDown) return;
                isPointerDown = false;
                endLongPress();
                overlay.style.transform = 'translateY(0)';
                overlay.style.opacity = '1';
                this.isDragging = false;
                this.dragOffset = 0;
            });
        };

        addTouch(leftZone, () => this.previous());
        addTouch(rightZone, () => this.next());

        tapZones.appendChild(leftZone);
        tapZones.appendChild(rightZone);
        content.appendChild(tapZones);

        const hint = createEl('div', { className: 'story-hint' });
        hint.textContent = 'Tap sides to navigate, hold to pause, swipe down to close';
        content.appendChild(hint);

        this.renderProgressBars();
    },

    currentStory() {
        const group = this.groups[this.groupIndex];
        if (!group) return null;
        return group.stories[this.storyIndex] || null;
    },

    setupStory() {
        this.clearTimer();
        const story = this.currentStory();
        if (!story) {
            this.close();
            return;
        }

        this.markViewed(story);
        this.renderStoryMedia();
        this.renderProgressBars();
        this.updateTopBar();

        if (story.media_type === 'video' || story.mediaType === 'video') {
            this.progress = 0;
        } else {
            this.progress = 0;
            this.startImageTimer();
        }
    },

    updateTopBar() {
        const story = this.currentStory();
        if (!story) return;
        const userInfo = document.querySelector('.story-top-bar .user-info');
        if (userInfo) {
            clearEl(userInfo);
            userInfo.appendChild(renderAvatar(story.user, 36));
            userInfo.appendChild(createEl('span', { className: 'username', text: story.user.username }));
        }
        const menuBtn = document.querySelector('.story-top-bar .story-menu-btn');
        if (menuBtn) {
            menuBtn.style.display = canManageContent(story.user.id, state.user) ? 'flex' : 'none';
        }
    },

    renderStoryMedia() {
        const content = document.getElementById('story-content');
        const old = content.querySelector('#story-media');
        if (old) old.remove();

        const story = this.currentStory();
        if (!story) return;

        const url = storyMediaUrl(story);
        const isVideo = story.media_type === 'video' || story.mediaType === 'video';
        const mediaWrap = createEl('div', {
            id: 'story-media',
            style: 'position:absolute;inset:0;display:flex;align-items:center;justify-content:center;'
        });

        if (isVideo) {
            const video = createEl('video', {
                src: url,
                autoplay: true,
                playsinline: true,
                muted: false,
                style: 'max-width:100%;max-height:100%;object-fit:contain;'
            });
            video.addEventListener('ended', () => this.next());
            video.addEventListener('loadedmetadata', () => {});
            video.addEventListener('error', () => {
                mediaWrap.innerHTML = '<p style="color:white">Could not load video</p>';
            });
            this.currentMedia = video;
            mediaWrap.appendChild(video);
        } else {
            const img = createEl('img', {
                src: url,
                alt: '',
                style: 'max-width:100%;max-height:100%;object-fit:contain;'
            });
            img.onerror = () => { mediaWrap.innerHTML = '<p style="color:white">Could not load image</p>'; };
            this.currentMedia = img;
            mediaWrap.appendChild(img);
        }

        content.insertBefore(mediaWrap, content.firstChild);
    },

    renderProgressBars() {
        const wrap = document.getElementById('story-progress');
        if (!wrap) return;
        clearEl(wrap);
        const group = this.groups[this.groupIndex];
        if (!group) return;
        group.stories.forEach((_, idx) => {
            const bar = createEl('div', { className: 'story-progress-bar' });
            const fill = createEl('div', { className: 'story-progress-fill' });
            if (idx < this.storyIndex) fill.style.width = '100%';
            else if (idx === this.storyIndex) fill.style.width = (this.progress * 100) + '%';
            else fill.style.width = '0%';
            bar.appendChild(fill);
            wrap.appendChild(bar);
        });
    },

    startImageTimer() {
        this.clearTimer();
        const duration = 5000;
        const interval = 50;
        this.timer = setInterval(() => {
            if (this.isPaused) return;
            this.progress += interval / duration;
            this.renderProgressBars();
            if (this.progress >= 1) {
                this.next();
            }
        }, interval);
    },

    clearTimer() {
        if (this.timer) {
            clearInterval(this.timer);
            this.timer = null;
        }
    },

    updatePause() {
        if (this.currentMedia && this.currentMedia.tagName === 'VIDEO') {
            if (this.isPaused) this.currentMedia.pause();
            else this.currentMedia.play();
        }
    },

    next() {
        this.clearTimer();
        const group = this.groups[this.groupIndex];
        if (!group) return;
        if (this.storyIndex < group.stories.length - 1) {
            this.storyIndex++;
            this.setupStory();
        } else if (this.groupIndex < this.groups.length - 1) {
            this.groupIndex++;
            this.storyIndex = 0;
            this.setupStory();
        } else {
            this.close();
        }
    },

    previous() {
        this.clearTimer();
        if (this.storyIndex > 0) {
            this.storyIndex--;
            this.setupStory();
        } else if (this.groupIndex > 0) {
            this.groupIndex--;
            this.storyIndex = Math.max(this.groups[this.groupIndex].stories.length - 1, 0);
            this.setupStory();
        } else {
            this.progress = 0;
            this.setupStory();
        }
    },

    markViewed(story) {
        if (this.viewedIds.has(story.id) || story.viewed) return;
        this.viewedIds.add(story.id);
        setTimeout(() => {
            const current = this.currentStory();
            if (current && current.id === story.id) {
                markStoryViewed(story.id).catch(() => {});
            }
        }, 300);
    },

    async deleteCurrent() {
        if (this.isDeleting) return;
        const story = this.currentStory();
        if (!story) return;
        if (!canManageContent(story.user.id, state.user)) return;
        if (!confirmAction('Delete this story? This cannot be undone.')) return;

        this.isDeleting = true;
        const menuBtn = document.querySelector('.story-top-bar .story-menu-btn');
        if (menuBtn) menuBtn.disabled = true;

        try {
            await deleteStory(story.id);
            this.groups[this.groupIndex].stories.splice(this.storyIndex, 1);
            if (this.groups[this.groupIndex].stories.length === 0) {
                this.groups.splice(this.groupIndex, 1);
                if (this.groups.length === 0) {
                    this.close();
                    return;
                }
                if (this.groupIndex >= this.groups.length) this.groupIndex = this.groups.length - 1;
                this.storyIndex = 0;
            } else if (this.storyIndex >= this.groups[this.groupIndex].stories.length) {
                this.storyIndex = this.groups[this.groupIndex].stories.length - 1;
            }
            this.setupStory();
        } catch (err) {
            showAlert(err.message);
        } finally {
            this.isDeleting = false;
            if (menuBtn) menuBtn.disabled = false;
        }
    },

    close() {
        this.clearTimer();
        const overlay = document.getElementById('story-viewer-overlay');
        if (overlay) overlay.remove();
        this.currentMedia = null;
        this.isDeleting = false;
    }
};
