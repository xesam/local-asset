console.log("[LocalAssetSample] static/app.js loaded");

window.addEventListener("DOMContentLoaded", () => {
  const status = document.getElementById("status");
  const mappedLogo = document.getElementById("mappedLogo");
  const httpLogo = document.getElementById("httpLogo");
  const mappedResult = document.getElementById("mappedResult");
  const httpResult = document.getElementById("httpResult");

  if (status) {
    status.textContent = "This page compares a library-handled image with a same-kind image that stays on WebView's default loading path.";
  }

  bindImageState(
    mappedLogo,
    mappedResult,
    "LocalAsset image loaded from local-asset://assets.demo.local/static/images/logo.svg",
    "LocalAsset image failed to load",
    "[LocalAssetSample] mapped LocalAsset image rendered",
    "[LocalAssetSample] mapped LocalAsset image failed",
  );
  bindImageState(
    httpLogo,
    httpResult,
    "Comparison image loaded through WebView's default resource path",
    "Comparison image failed to load through the default resource path",
    "[LocalAssetSample] comparison image rendered without LocalAsset handling",
    "[LocalAssetSample] comparison image failed without LocalAsset handling",
  );
});

function bindImageState(image, label, successText, errorText, successLog, errorLog) {
  if (!image || !label) {
    return;
  }
  const onSuccess = () => {
    label.textContent = successText;
    console.log(successLog);
  };
  const onError = () => {
    label.textContent = errorText;
    console.log(errorLog);
  };
  image.addEventListener("load", onSuccess);
  image.addEventListener("error", onError);
  if (image.complete) {
    if (image.naturalWidth > 0) {
      onSuccess();
    } else {
      onError();
    }
  }
}
