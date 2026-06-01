
const themeToggle = document.querySelector('.theme-toggle');
const themeIcon = document.querySelector('#themeIcon');
const btnNav = document.querySelector('.btn-nav');
const downloadCard = document.querySelector('.dl-card');
const downloadBadge = document.querySelector('[data-download-badge]');
const downloadIcon = document.querySelector('[data-download-icon]');
const downloadTitle = document.querySelector('[data-download-title]');
const downloadSubtitle = document.querySelector('[data-download-subtitle]');
const downloadAlert = document.querySelector('[data-download-alert]');
const downloadAlertTitle = document.querySelector('[data-download-alert-title]');
const downloadAlertText = document.querySelector('[data-download-alert-text]');
const downloadButton = document.querySelector('[data-download-button]');

function setTheme(theme) {
    document.body.dataset.theme = theme;
    const isDark = theme === 'dark';
    themeIcon.textContent = isDark ? '☀️' : '🌙';
    themeToggle.setAttribute('aria-label', isDark ? 'Switch to light mode' : 'Switch to dark mode');
    themeToggle.setAttribute('aria-pressed', String(isDark));
    localStorage.setItem('zam-theme', theme);
}

// FIX: read savedTheme after DOM is ready (script is deferred by being at end of body)
const savedTheme = localStorage.getItem('zam-theme');
setTheme(savedTheme || 'light');

// FIX: btn-nav — restore full label on desktop, keep icon-only on mobile via CSS
function updateBtnNavLabel() {
    const isMobile = window.innerWidth <= 768;
    btnNav.textContent = isMobile ? '⬇️' : '⬇️ Download Free';
}
updateBtnNavLabel();
window.addEventListener('resize', updateBtnNavLabel);

function getDeviceType() {
    const ua = navigator.userAgent || '';
    const platform = navigator.platform || '';
    const maxTouchPoints = navigator.maxTouchPoints || 0;
    const isIOS = /iPad|iPhone|iPod/.test(ua) || (platform === 'MacIntel' && maxTouchPoints > 1);
    const isMac = /Macintosh|Mac OS X/.test(ua) || platform.startsWith('Mac');
    const isAndroid = /Android/.test(ua);
    const isMobile = /Mobi|Android|iPhone|iPad|iPod/.test(ua) || maxTouchPoints > 1;

    if (isIOS || isMac) return 'unsupported';
    if (isAndroid) return 'android';
    if (!isMobile) return 'desktop';
    return 'other';
}

function setDownloadAlert(title, text) {
    downloadAlertTitle.textContent = title;
    downloadAlertText.textContent = text;
    downloadAlert.hidden = false;
}

function updateDownloadCard() {
    if (!downloadCard || !downloadButton) return;

    const deviceType = getDeviceType();
    downloadCard.classList.toggle('is-unsupported', deviceType === 'unsupported');
    downloadBadge.classList.toggle('is-warning', deviceType !== 'android');
    downloadButton.classList.toggle('btn-dl-grad', deviceType !== 'unsupported');
    downloadButton.classList.toggle('btn-dl-subtle', deviceType === 'unsupported');
    downloadAlert.hidden = true;

    if (deviceType === 'unsupported') {
        downloadBadge.textContent = 'Android APK';
        downloadIcon.textContent = '⚠️';
        downloadTitle.textContent = 'Unsupported Device';
        downloadSubtitle.textContent = 'Zam is built for Android phones only.';
        downloadButton.textContent = 'Download APK anyway';
        setDownloadAlert('This file will not install on iOS or macOS.', 'If you still need the APK for another Android device, you can download it anyway.');
        return;
    }

    if (deviceType === 'desktop') {
        downloadBadge.textContent = 'Android APK';
        downloadIcon.textContent = '💻';
        downloadTitle.textContent = 'Android APK File';
        downloadSubtitle.textContent = 'Transfer it to an Android 12+ device to install.';
        downloadButton.textContent = '⬇️ Download APK';
        setDownloadAlert('Heads up: this is an APK file.', 'It installs on Android devices, not directly on Windows, macOS, or desktop browsers.');
        return;
    }

    downloadBadge.textContent = 'Free Download';
    downloadIcon.textContent = '📱';
    downloadTitle.textContent = 'Android';
    downloadSubtitle.textContent = 'Requires Android 12 or higher';
    downloadButton.textContent = '⬇️ Download APK';
}

updateDownloadCard();

themeToggle.addEventListener('click', () => {
    themeToggle.classList.remove('spin');
    void themeToggle.offsetWidth;
    themeToggle.classList.add('spin');
    setTheme(document.body.dataset.theme === 'dark' ? 'light' : 'dark');
});

themeToggle.addEventListener('animationend', () => {
    themeToggle.classList.remove('spin');
});

const revealTargets = document.querySelectorAll(
    '.about-inner, .feat-card, .how-inner > .section-label, .how-inner > h2, .step, .download-inner, .install-step, .sysreq, footer'
);

revealTargets.forEach((target) => target.classList.add('reveal'));

const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
        if (entry.isIntersecting) {
            entry.target.classList.add('visible');
            observer.unobserve(entry.target);
        }
    });
}, { threshold: 0.12 });

document.querySelectorAll('.reveal').forEach((target) => observer.observe(target));
