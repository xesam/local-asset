console.log("[LocalAssetSample] pkg/home.js loaded");

window.addEventListener("DOMContentLoaded", () => {
  const summary = document.getElementById("summary");
  if (summary) {
    summary.textContent = "Bundle loaded from local-asset://cdn.demo.local/pkg/*";
  }
});
