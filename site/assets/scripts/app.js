(function () {
  var revealNodes = document.querySelectorAll('.reveal');

  if (revealNodes.length && 'IntersectionObserver' in window) {
    var revealObserver = new IntersectionObserver(
      function (entries, observer) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add('is-visible');
            observer.unobserve(entry.target);
          }
        });
      },
      {
        threshold: 0.2,
        rootMargin: '0px 0px -10% 0px'
      }
    );

    revealNodes.forEach(function (node) {
      revealObserver.observe(node);
    });
  } else {
    revealNodes.forEach(function (node) {
      node.classList.add('is-visible');
    });
  }

  var yearTargets = document.querySelectorAll('[data-year]');
  var year = new Date().getFullYear();
  yearTargets.forEach(function (node) {
    node.textContent = String(year);
  });
})();
