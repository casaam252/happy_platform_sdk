0.1.0

BREAKING CHANGE: Updated the HappyPlatform.initialize() method. It now accepts a Map<String, String> of projects to support multiple API keys, making the SDK more flexible and scalable.

HappyPlatform.firestore() now accepts an optional projectName to switch between initialized projects.

Simplified the internal Dio instance management for better multi-project support.

0.0.1

Initial release of the Happy Platform SDK.

Supports full CRUD operations (Create, Read, Update, Delete).

Provides a simple, fluent API for interacting with your Happy Platform backend.