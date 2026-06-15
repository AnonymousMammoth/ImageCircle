/**
 * Browser getUserMedia camera with photo capture and hold-to-record video.
 */

const cameraComponent = {
    stream: null,
    videoEl: null,
    onComplete: null,
    overlay: null,
    mediaRecorder: null,
    recordedChunks: [],
    recordTimer: null,
    isRecording: false,
    holdStartTime: 0,
    holdThresholdMs: 250,
    didRecord: false,

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
        // Tap = photo, hold = video
        shutter.addEventListener('pointerdown', (e) => this.onShutterDown(e));
        shutter.addEventListener('pointerup', (e) => this.onShutterUp(e));
        shutter.addEventListener('pointerleave', (e) => this.onShutterUp(e));
        shutter.addEventListener('pointercancel', (e) => this.onShutterUp(e));
        // Prevent context menu on long press
        shutter.addEventListener('contextmenu', (e) => e.preventDefault());

        const fileInput = createEl('input', { type: 'file', accept: 'image/*,video/*', className: 'hidden', id: 'camera-file' });
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
                audio: true
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
                audio: true
            });
            this.videoEl.srcObject = this.stream;
        } catch (err) {
            this.startCamera();
        }
    },

    onShutterDown(e) {
        if (this.isRecording || !this.stream) return;
        if (e && e.target) e.target.setPointerCapture(e.pointerId);
        this.holdStartTime = Date.now();
        this.didRecord = false;
        // If held long enough, start recording
        this.recordTimer = setTimeout(() => {
            this.startRecording();
        }, this.holdThresholdMs);
    },

    onShutterUp(e) {
        if (e && e.target && e.target.hasPointerCapture && e.target.hasPointerCapture(e.pointerId)) {
            try { e.target.releasePointerCapture(e.pointerId); } catch (_) {}
        }
        if (this.recordTimer) {
            clearTimeout(this.recordTimer);
            this.recordTimer = null;
        }
        if (this.isRecording) {
            this.stopRecording();
        } else if (!this.didRecord) {
            const elapsed = Date.now() - this.holdStartTime;
            if (elapsed < this.holdThresholdMs) {
                this.takePhoto();
            }
        }
    },

    takePhoto() {
        if (!this.videoEl || !this.videoEl.videoWidth) return;
        this.didRecord = true;
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

    startRecording() {
        if (!this.stream || this.isRecording) return;

        const mimeType = this.getRecorderMimeType();
        if (!mimeType) {
            this.showError('Video recording is not supported on this device.');
            this.didRecord = true;
            return;
        }

        this.isRecording = true;
        this.didRecord = true;
        this.recordedChunks = [];
        const shutter = document.getElementById('camera-shutter');
        if (shutter) shutter.classList.add('recording');

        try {
            this.mediaRecorder = new MediaRecorder(this.stream, { mimeType });
        } catch (err) {
            this.showError('Video recording is not supported on this device.');
            this.isRecording = false;
            if (shutter) shutter.classList.remove('recording');
            return;
        }

        this.mediaRecorder.ondataavailable = (e) => {
            if (e.data && e.data.size > 0) this.recordedChunks.push(e.data);
        };

        this.mediaRecorder.onstop = () => {
            const blob = new Blob(this.recordedChunks, { type: mimeType });
            const file = new File([blob], 'camera-video.mp4', { type: mimeType });
            this.complete(file);
        };

        this.mediaRecorder.start();
    },

    stopRecording() {
        if (!this.isRecording || !this.mediaRecorder) return;
        if (this.mediaRecorder.state !== 'inactive') {
            this.mediaRecorder.stop();
        }
        this.isRecording = false;
        const shutter = document.getElementById('camera-shutter');
        if (shutter) shutter.classList.remove('recording');
    },

    getRecorderMimeType() {
        if (MediaRecorder.isTypeSupported('video/mp4')) {
            return 'video/mp4';
        }
        return '';
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
        if (this.recordTimer) {
            clearTimeout(this.recordTimer);
            this.recordTimer = null;
        }
        if (this.isRecording && this.mediaRecorder && this.mediaRecorder.state !== 'inactive') {
            this.mediaRecorder.stop();
        }
        this.isRecording = false;
        if (this.stream) {
            this.stream.getTracks().forEach(track => track.stop());
            this.stream = null;
        }
        if (this.overlay) {
            this.overlay.remove();
            this.overlay = null;
        }
        this.videoEl = null;
        this.mediaRecorder = null;
        this.recordedChunks = [];
        this.didRecord = false;
    }
};
