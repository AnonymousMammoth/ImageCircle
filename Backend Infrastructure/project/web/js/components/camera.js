/**
 * Browser getUserMedia camera with photo capture.
 * Video recording is optional; we keep it simple and photo-first.
 */

const cameraComponent = {
    stream: null,
    videoEl: null,
    onComplete: null,
    overlay: null,

    open(onComplete) {
        this.onComplete = onComplete;
        this.render();
        this.startCamera();
    },

    render() {
        const existing = document.getElementById('camera-overlay');
        if (existing) existing.remove();

        this.overlay = createEl('div', { id: 'camera-overlay', className: 'fullscreen-overlay' });

        const header = createEl('div', { className: 'story-top-bar' });
        const spacer = createEl('div');
        const closeBtn = createEl('button', { className: 'story-close-btn' });
        closeBtn.innerHTML = shell.icons.close;
        closeBtn.addEventListener('click', () => this.close());
        header.appendChild(spacer);
        header.appendChild(closeBtn);

        this.videoEl = createEl('video', { className: 'camera-video', autoplay: true, playsinline: true });

        const controls = createEl('div', { className: 'camera-controls' });
        const switchBtn = createEl('button', { className: 'camera-library-btn' });
        switchBtn.innerHTML = shell.icons.camera;
        switchBtn.addEventListener('click', () => this.switchCamera());

        const shutter = createEl('button', { className: 'camera-shutter', id: 'camera-shutter' });
        shutter.addEventListener('click', () => this.takePhoto());

        const fileInput = createEl('input', { type: 'file', accept: 'image/*', className: 'hidden', id: 'camera-file' });
        fileInput.addEventListener('change', (e) => {
            if (e.target.files && e.target.files[0]) {
                this.complete(e.target.files[0]);
            }
        });

        const libraryBtn = createEl('button', { className: 'camera-library-btn' });
        libraryBtn.innerHTML = shell.icons.photo;
        libraryBtn.addEventListener('click', () => fileInput.click());

        controls.appendChild(libraryBtn);
        controls.appendChild(shutter);
        controls.appendChild(switchBtn);

        this.overlay.appendChild(header);
        this.overlay.appendChild(this.videoEl);
        this.overlay.appendChild(fileInput);
        this.overlay.appendChild(controls);
        document.body.appendChild(this.overlay);
    },

    async startCamera() {
        try {
            this.stream = await navigator.mediaDevices.getUserMedia({
                video: { facingMode: 'environment' },
                audio: false
            });
            this.videoEl.srcObject = this.stream;
        } catch (err) {
            this.showError('Could not access camera. Please allow camera permissions.');
        }
    },

    async switchCamera() {
        if (!this.stream) return;
        const tracks = this.stream.getVideoTracks();
        if (!tracks.length) return;
        const current = tracks[0];
        const facing = current.getSettings().facingMode;
        const newFacing = facing === 'user' ? 'environment' : 'user';
        current.stop();
        try {
            this.stream = await navigator.mediaDevices.getUserMedia({
                video: { facingMode: newFacing },
                audio: false
            });
            this.videoEl.srcObject = this.stream;
        } catch (err) {
            // Try to restore previous
            this.startCamera();
        }
    },

    takePhoto() {
        if (!this.videoEl || !this.videoEl.videoWidth) return;
        const canvas = document.createElement('canvas');
        canvas.width = this.videoEl.videoWidth;
        canvas.height = this.videoEl.videoHeight;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(this.videoEl, 0, 0);
        canvas.toBlob((blob) => {
            if (blob) {
                const file = new File([blob], 'camera-photo.jpg', { type: 'image/jpeg' });
                this.complete(file);
            }
        }, 'image/jpeg', 0.92);
    },

    complete(file) {
        if (this.onComplete) this.onComplete(file);
        this.close();
    },

    showError(message) {
        const placeholder = createEl('div', { className: 'camera-placeholder' });
        placeholder.innerHTML = shell.icons.warning;
        const title = createEl('h3', { text: 'Camera Error' });
        const desc = createEl('p', { text: message });
        placeholder.appendChild(title);
        placeholder.appendChild(desc);
        this.overlay.insertBefore(placeholder, this.videoEl);
        this.videoEl.style.display = 'none';
    },

    close() {
        if (this.stream) {
            this.stream.getTracks().forEach(track => track.stop());
            this.stream = null;
        }
        if (this.overlay) {
            this.overlay.remove();
            this.overlay = null;
        }
        this.videoEl = null;
    }
};
