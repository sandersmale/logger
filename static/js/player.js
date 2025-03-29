document.addEventListener('DOMContentLoaded', function() {
    // Elements
    const audio = document.getElementById('audioPlayer');
    const timeIndicator = document.getElementById('timeIndicator');
    const btnPlayPause = document.getElementById('btnPlayPause');
    const btnBack15 = document.getElementById('btnBack15');
    const btnBack120 = document.getElementById('btnBack120');
    const btnFwd15 = document.getElementById('btnFwd15');
    const btnFwd120 = document.getElementById('btnFwd120');
    const btnSetStart = document.getElementById('btnSetStart');
    const btnSetEnd = document.getElementById('btnSetEnd');
    const btnDownloadFragment = document.getElementById('btnDownloadFragment');
    const btnDownloadFull = document.getElementById('btnDownloadFull');
    const startInput = document.getElementById('start');
    const endInput = document.getElementById('end');
    const markerDisplay = document.getElementById('markerDisplay');
    const downloadForm = document.getElementById('downloadForm');
    
    // State
    let isPlaying = false;
    
    // Helper functions
    function formatTime(seconds) {
        if (isNaN(seconds)) return "--:--";
        
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return String(mins).padStart(2, '0') + ":" + String(secs).padStart(2, '0');
    }
    
    function updateMarkerDisplay() {
        const startVal = startInput.value;
        const endVal = endInput.value;
        
        markerDisplay.textContent = "Start: " + (startVal ? formatTime(parseFloat(startVal)) : "--:--") + 
                                   ", Eind: " + (endVal ? formatTime(parseFloat(endVal)) : "--:--");
                                   
        // Enable/disable download fragment button
        if (startVal && endVal && parseFloat(endVal) > parseFloat(startVal)) {
            btnDownloadFragment.disabled = false;
        } else {
            btnDownloadFragment.disabled = true;
        }
    }
    
    // Event listeners
    audio.addEventListener('timeupdate', () => {
        let currentTime = formatTime(audio.currentTime);
        let duration = formatTime(audio.duration);
        timeIndicator.textContent = currentTime + " / " + duration;
    });
    
    audio.addEventListener('play', () => {
        isPlaying = true;
        btnPlayPause.innerHTML = '<i class="fas fa-pause"></i>';
        btnPlayPause.setAttribute('aria-label', 'Pauzeren');
    });
    
    audio.addEventListener('pause', () => {
        isPlaying = false;
        btnPlayPause.innerHTML = '<i class="fas fa-play"></i>';
        btnPlayPause.setAttribute('aria-label', 'Afspelen');
    });
    
    // Navigation controls
    btnBack120.addEventListener('click', () => {
        audio.currentTime = Math.max(0, audio.currentTime - 120);
    });
    
    btnBack15.addEventListener('click', () => {
        audio.currentTime = Math.max(0, audio.currentTime - 15);
    });
    
    btnPlayPause.addEventListener('click', () => {
        if (isPlaying) {
            audio.pause();
        } else {
            audio.play();
        }
    });
    
    btnFwd15.addEventListener('click', () => {
        if (!isNaN(audio.duration)) {
            audio.currentTime = Math.min(audio.duration, audio.currentTime + 15);
        }
    });
    
    btnFwd120.addEventListener('click', () => {
        if (!isNaN(audio.duration)) {
            audio.currentTime = Math.min(audio.duration, audio.currentTime + 120);
        }
    });
    
    // Marker controls
    btnSetStart.addEventListener('click', () => {
        startInput.value = audio.currentTime;
        updateMarkerDisplay();
    });
    
    btnSetEnd.addEventListener('click', () => {
        endInput.value = audio.currentTime;
        updateMarkerDisplay();
    });
    
    // Download controls
    btnDownloadFull.addEventListener('click', () => {
        startInput.value = '';
        endInput.value = '';
        downloadForm.submit();
    });
    
    // Keyboard controls
    document.addEventListener('keydown', (e) => {
        // Only process if not typing in an input field
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
            return;
        }
        
        switch (e.code) {
            case 'Space':
                e.preventDefault();
                btnPlayPause.click();
                break;
            case 'ArrowLeft':
                e.preventDefault();
                if (e.shiftKey) {
                    btnBack120.click();
                } else {
                    btnBack15.click();
                }
                break;
            case 'ArrowRight':
                e.preventDefault();
                if (e.shiftKey) {
                    btnFwd120.click();
                } else {
                    btnFwd15.click();
                }
                break;
            case 'KeyM':
                if (e.shiftKey) {
                    btnSetEnd.click();
                } else {
                    btnSetStart.click();
                }
                break;
        }
    });
    
    // Initialize marker display
    updateMarkerDisplay();
    
    // Focus the play button initially for keyboard navigation
    btnPlayPause.focus();
});
