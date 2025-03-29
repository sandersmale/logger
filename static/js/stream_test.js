document.addEventListener('DOMContentLoaded', function() {
    // Elements
    const testStreamBtn = document.getElementById('testStreamBtn');
    const testStreamResult = document.getElementById('testStreamResult');
    const testStreamForm = document.getElementById('testStreamForm');
    const modalTestResult = document.getElementById('modalTestResult');
    const streamUrlInput = document.getElementById('recording_url');
    const testUrlInput = document.getElementById('url');
    const submitTestBtn = document.getElementById('submitTestBtn');
    
    // Bootstrap modal
    let testStreamModal;
    if (document.getElementById('testStreamModal')) {
        testStreamModal = new bootstrap.Modal(document.getElementById('testStreamModal'));
    }
    
    // Helper function to show result with appropriate styling
    function displayResult(element, success, message, url = null) {
        let html = '';
        
        if (success) {
            html = `
                <div class="alert alert-success">
                    <i class="fas fa-check-circle me-2"></i>${message}
                </div>
            `;
            
            if (url) {
                html += `
                    <div class="alert alert-info">
                        <i class="fas fa-info-circle me-2"></i>Werkende URL: <code>${url}</code>
                        <button class="btn btn-sm btn-primary mt-2" onclick="useThisUrl('${url}')">
                            Deze URL gebruiken
                        </button>
                    </div>
                `;
            }
        } else {
            html = `
                <div class="alert alert-danger">
                    <i class="fas fa-exclamation-circle me-2"></i>${message}
                </div>
            `;
        }
        
        element.innerHTML = html;
    }
    
    // Function to test a stream URL
    function testStream(url, resultElement, modal = false) {
        // Show loading indicator
        resultElement.innerHTML = `
            <div class="alert alert-info">
                <div class="d-flex align-items-center">
                    <div class="spinner-border spinner-border-sm me-2" role="status">
                        <span class="visually-hidden">Laden...</span>
                    </div>
                    <div>
                        Stream wordt getest... Dit kan tot 10 seconden duren.
                    </div>
                </div>
            </div>
        `;
        
        // Make the API request
        fetch('/test_stream', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRFToken': document.querySelector('input[name="csrf_token"]').value
            },
            body: JSON.stringify({ url: url })
        })
        .then(response => response.json())
        .then(data => {
            if (data.status === 'OK') {
                displayResult(resultElement, true, 'Stream test succesvol!', data.stream_url);
                
                // If we're in the modal and the test was successful, offer to use this URL
                if (modal && data.stream_url) {
                    window.useThisUrl = function(url) {
                        streamUrlInput.value = url;
                        testStreamModal.hide();
                        // Also update the main form's result area
                        displayResult(testStreamResult, true, 'Stream test succesvol!', url);
                    };
                }
            } else {
                displayResult(resultElement, false, data.message || 'Fout bij het testen van de stream.');
            }
        })
        .catch(error => {
            console.error('Error:', error);
            displayResult(resultElement, false, 'Er is een fout opgetreden bij de verbinding met de server.');
        });
    }
    
    // Event Listeners
    if (testStreamBtn) {
        testStreamBtn.addEventListener('click', function() {
            const currentUrl = streamUrlInput.value.trim();
            
            if (currentUrl) {
                // If we have a URL in the form, test it directly
                testStream(currentUrl, testStreamResult);
            } else {
                // Otherwise open the modal for testing
                if (testUrlInput) {
                    testUrlInput.value = '';
                }
                if (modalTestResult) {
                    modalTestResult.innerHTML = '';
                }
                testStreamModal.show();
            }
        });
    }
    
    if (testStreamForm) {
        testStreamForm.addEventListener('submit', function(e) {
            e.preventDefault();
            const urlToTest = testUrlInput.value.trim();
            
            if (urlToTest) {
                testStream(urlToTest, modalTestResult, true);
            } else {
                modalTestResult.innerHTML = `
                    <div class="alert alert-danger">
                        <i class="fas fa-exclamation-circle me-2"></i>Voer een URL in om te testen.
                    </div>
                `;
            }
        });
    }
    
    // Add has_schedule toggle functionality
    const hasScheduleCheckbox = document.getElementById('has_schedule');
    if (hasScheduleCheckbox) {
        hasScheduleCheckbox.addEventListener('change', function() {
            const scheduleSection = document.querySelector('.schedule-section');
            if (scheduleSection) {
                scheduleSection.style.display = this.checked ? 'block' : 'none';
            }
        });
    }
});
