const filterButtons = document.querySelectorAll("[data-filter]");
const roadmapItems = document.querySelectorAll("[data-priority]");

filterButtons.forEach((button) => {
  button.addEventListener("click", () => {
    const selectedPriority = button.dataset.filter;

    filterButtons.forEach((candidate) => {
      const isSelected = candidate === button;
      candidate.classList.toggle("is-active", isSelected);
      candidate.setAttribute("aria-pressed", String(isSelected));
    });

    roadmapItems.forEach((item) => {
      const shouldShow = selectedPriority === "all" || item.dataset.priority === selectedPriority;
      item.classList.toggle("is-hidden", !shouldShow);
    });
  });
});
