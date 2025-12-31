// Fetch service with retry logic and exponential backoff

/**
 * Helper function to fetch with retry logic and exponential backoff
 */
export async function fetchWithRetry(
  url,
  options,
  maxRetries = 3,
  baseDelay = 1000,
  handledErrors = null,
) {
  let lastError;
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      // Add timeout to prevent hanging
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 10000); // 10 second timeout

      const response = await fetch(url, {
        ...options,
        signal: controller.signal,
        cache: "no-cache",
        mode: "cors",
        credentials: "omit",
      });

      clearTimeout(timeoutId);
      return response;
    } catch (error) {
      lastError = error;

      // Handle AbortError gracefully (timeout)
      if (error.name === "AbortError") {
        if (attempt < maxRetries - 1) {
          const delay = baseDelay * Math.pow(2, attempt);
          console.warn(
            `⚠️ [FETCH] Request timeout (attempt ${attempt + 1}/${maxRetries}), retrying in ${delay}ms...`,
          );
          if (handledErrors) {
            handledErrors.add(error);
          }
          await new Promise((resolve) => setTimeout(resolve, delay));
          continue;
        }
        break;
      }

      const isNetworkError =
        error.name === "TypeError" ||
        error.name === "NetworkError" ||
        error.message?.includes("Failed to fetch") ||
        error.message?.includes("QUIC") ||
        error.message?.includes("ERR_QUIC") ||
        error.message?.includes("NetworkError") ||
        error.message?.includes("network");

      if (isNetworkError && attempt < maxRetries - 1) {
        const delay = baseDelay * Math.pow(2, attempt);
        console.warn(
          `⚠️ [FETCH] Network error (attempt ${attempt + 1}/${maxRetries}), retrying in ${delay}ms...`,
          error.message || error.toString(),
        );
        if (handledErrors) {
          handledErrors.add(error);
        }
        await new Promise((resolve) => setTimeout(resolve, delay));
        continue;
      }

      break;
    }
  }

  // If we exhausted all retries, throw the last error with more context
  if (lastError) {
    const enhancedError = new Error(
      `Failed to fetch after ${maxRetries} attempts: ${lastError.message || lastError.toString()}. URL: ${url}`,
    );
    enhancedError.name = lastError.name || "NetworkError";
    enhancedError.cause = lastError;
    if (handledErrors) {
      handledErrors.add(enhancedError);
      handledErrors.add(lastError);
    }
    throw enhancedError;
  }

  const unknownError = new Error(`Failed to fetch: Unknown error. URL: ${url}`);
  if (handledErrors) {
    handledErrors.add(unknownError);
  }
  throw unknownError;
}
