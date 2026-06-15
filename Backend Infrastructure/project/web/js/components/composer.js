/**
 * Create composer screen: Photo/Text toggle, file picker, camera, caption, post/story.
 */

const composerComponent = {
    mode: 'photo',
    selectedFile: null,
    mediaType: 'image',
    isPosting: false,
    previewObjectUrl: null,

    render(container) {
        clearEl(container);
        container.className = 'screen-scroll tab-content';

        const header = createEl('div', { className: 'top-header' });
        const title = createEl('h1', { text: 'Create' });
        header.appendChild(title);
        container.appendChild(header);

        const body = createEl('div', { className: 'composer-body' });

        const modeToggle = createEl('div', { className: 'feed-filter' });
        modeToggle.appendChild(this.renderModeToggle());
        body.appendChild(modeToggle);

        const contentArea = createEl('div', { id: 'composer-content' });
        body.appendChild(contentArea);

        container.appendChild(body);

        this.renderContent(contentArea);
    },

    revokePreviewUrl() {
        if (this.previewObjectUrl) {
            URL.revokeObjectURL(this.previewObjectUrl);
            this.previewObjectUrl = null;
        }
    },

    renderModeToggle() {
        const wrap = createEl('div', { className: 'segmented-control' });
        const options = [
            { key: 'photo', label: 'Photo' },
            { key: 'text', label: 'Text' }
        ];
        options.forEach(opt => {
            const btn = createEl('button', { type: 'button', className: opt.key === this.mode ? 'active' : '' });
            btn.textContent = opt.label;
            btn.addEventListener('click', () => {
                this.mode = opt.key;
                this.revokePreviewUrl();
                this.selectedFile = null;
                this.mediaType = 'image';
                const content = document.getElementById('composer-content');
                if (content) this.renderContent(content);
                Array.from(wrap.children).forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
            });
            wrap.appendChild(btn);
        });
        return wrap;
    },

    renderContent(container) {
        clearEl(container);
        if (this.mode === 'photo') {
            container.appendChild(this.renderPhotoComposer());
        } else {
            container.appendChild(this.renderTextComposer());
        }
    },

    renderPhotoComposer() {
        const wrap = createEl('div', { className: 'composer-mode-wrap composer-photo-wrap', style: 'display:flex;flex-direction:column;flex:1;' });

        if (this.selectedFile) {
            this.revokePreviewUrl();
            const preview = createEl('div', { className: 'composer-preview' });
            const url = URL.createObjectURL(this.selectedFile);
            this.previewObjectUrl = url;
            if (this.mediaType === 'video') {
                preview.appendChild(createEl('video', { src: url, controls: true, autoplay: false }));
            } else {
                preview.appendChild(createEl('img', { src: url }));
            }
            wrap.appendChild(preview);

            const captionArea = createEl('div', { className: 'composer-caption' });
            const captionInput = createEl('textarea', { id: 'composer-caption', placeholder: 'Write a caption...' });
            captionArea.appendChild(captionInput);
            wrap.appendChild(captionArea);

            const actions = createEl('div', { className: 'composer-actions' });
            const postBtn = createEl('button', { className: 'btn btn-primary' });
            postBtn.textContent = this.mediaType === 'video' ? 'Post Video to Feed' : 'Post to Feed';
            postBtn.addEventListener('click', () => this.submitPhoto(captionInput.value, false));

            const storyBtn = createEl('button', { className: 'btn btn-secondary' });
            storyBtn.textContent = 'Add to Story';
            storyBtn.addEventListener('click', () => this.submitPhoto(captionInput.value, true));

            actions.appendChild(postBtn);
            actions.appendChild(storyBtn);
            wrap.appendChild(actions);
        } else {
            const placeholder = createEl('div', { className: 'empty-state' });
            placeholder.innerHTML = shell.icons.photo;
            const title = createEl('h3', { text: 'Choose a photo or video' });
            const desc = createEl('p', { text: 'Select from your library, or tap/hold the camera shutter to take a photo or record a video.' });
            placeholder.appendChild(title);
            placeholder.appendChild(desc);

            const actions = createEl('div', { style: 'display:flex;flex-direction:column;gap:12px;padding:0 32px 40px;' });

            const fileInput = createEl('input', { type: 'file', id: 'composer-file', accept: 'image/*,video/*', className: 'hidden' });
            fileInput.addEventListener('change', (e) => this.handleFileSelect(e.target.files[0]));

            const libraryBtn = createEl('button', { className: 'btn btn-primary' });
            libraryBtn.textContent = 'Choose from Library';
            libraryBtn.addEventListener('click', () => fileInput.click());

            const cameraBtn = createEl('button', { className: 'btn btn-secondary' });
            cameraBtn.textContent = 'Take Photo or Video';
            cameraBtn.addEventListener('click', () => cameraComponent.open((file) => this.handleFileSelect(file)));

            actions.appendChild(fileInput);
            actions.appendChild(libraryBtn);
            actions.appendChild(cameraBtn);

            wrap.appendChild(placeholder);
            wrap.appendChild(actions);
        }

        return wrap;
    },

    renderTextComposer() {
        const wrap = createEl('div', { className: 'composer-mode-wrap composer-text-wrap', style: 'display:flex;flex-direction:column;flex:1;padding:16px;' });
        const avatar = renderAvatar(state.user, 40);
        const editorWrap = createEl('div', { style: 'display:flex;gap:12px;flex:1;' });
        const editor = createEl('textarea', {
            id: 'text-post-input',
            placeholder: "What's on your mind?",
            style: 'flex:1;min-height:120px;resize:none;'
        });
        editorWrap.appendChild(avatar);
        editorWrap.appendChild(editor);
        wrap.appendChild(editorWrap);

        const postBtn = createEl('button', { className: 'btn btn-primary', style: 'margin-top:16px;' });
        postBtn.textContent = 'Post';
        postBtn.addEventListener('click', () => this.submitText(editor.value));
        wrap.appendChild(postBtn);

        return wrap;
    },

    handleFileSelect(file) {
        if (!file) {
            this.revokePreviewUrl();
            this.selectedFile = null;
            this.mediaType = 'image';
            const content = document.getElementById('composer-content');
            if (content) this.renderContent(content);
            return;
        }
        this.revokePreviewUrl();
        this.selectedFile = file;
        if (file.type.startsWith('video/')) {
            this.mediaType = 'video';
        } else {
            this.mediaType = 'image';
        }
        const content = document.getElementById('composer-content');
        if (content) this.renderContent(content);
    },

    async submitText(text) {
        const trimmed = text.trim();
        if (!trimmed) return;
        this.setLoading(true);
        try {
            await createTextPost(trimmed);
            router.navigate('/');
        } catch (err) {
            showAlert(err.message);
        } finally {
            this.setLoading(false);
        }
    },

    async submitPhoto(caption, asStory) {
        if (!this.selectedFile) return;
        this.setLoading(true);
        try {
            const onProgress = (p) => this.updateProgress(p * 100);
            if (asStory) {
                await createStory(this.selectedFile, this.mediaType, null, onProgress);
            } else {
                await createMediaPost(this.selectedFile, caption, null, onProgress);
            }
            this.revokePreviewUrl();
            this.selectedFile = null;
            this.mediaType = 'image';
            router.navigate('/');
        } catch (err) {
            showAlert(err.message);
            this.setLoading(false);
        }
    },

    setLoading(loading) {
        this.isPosting = loading;
        const content = document.getElementById('composer-content');
        if (!content) return;

        const buttons = content.querySelectorAll('button');
        buttons.forEach(btn => btn.disabled = loading);

        if (loading) {
            const existing = content.querySelector('.composer-progress');
            if (!existing) {
                const progress = createEl('div', { className: 'composer-progress' });
                progress.innerHTML = '<div class="progress-bar"><div class="progress-fill" style="width:0%"></div></div><div class="progress-text">Uploading...</div>';
                content.appendChild(progress);
            }
        } else {
            const progress = content.querySelector('.composer-progress');
            if (progress) progress.remove();
        }
    },

    updateProgress(percent) {
        const fill = document.querySelector('.composer-progress .progress-fill');
        const text = document.querySelector('.composer-progress .progress-text');
        if (fill) fill.style.width = percent + '%';
        if (text) text.textContent = 'Uploading... ' + Math.round(percent) + '%';
    }
};
