
const themeToggle = document.querySelector('.theme-toggle');
const themeIcon = document.querySelector('#themeIcon');
const btnNav = document.querySelector('.btn-nav');

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
