0.7.0

last update

0.6.0

Updated auth

0.6.0

Updated authantciation

0.5.0

BIG FEATURE: Added support for Auth service for managing project users.

Introduced HappyPlatform.auth() to access the new authentication service.

Added ProjectAuth class that requires projectId and developerAuthToken (JWT).

Features include:

createUser() – Add new user with email, password, and full name.

listUsers() – Fetch all users in a project.

updateUser() – Update user details by ID.

deleteUser() – Delete a user by ID.

0.4.0

BIG FEATURE: Added support for Realtime Database via WebSockets.

Introduced HappyPlatform.realtimeDatabase() to access the new service.

Added RealtimeDatabase and DatabaseReference classes for live data synchronization.

Supports onValue() for listening to streams, set() for writing data, and off() to unsubscribe.

Includes goOnline() and goOffline() for manual connection management.

0.3.0

BIG FEATURE: Added support for Realtime Database via WebSockets.

New HappyPlatform.realtimeDatabase() entry point.

Added RealtimeDatabase and DatabaseReference classes for live data synchronization.

Supports onValue() for listening to streams and set() for writing data.

0.2.0

FEATURE: Added support for advanced queries (where, orderBy, limit).

Introduced a powerful Query class that enables chaining query methods.

CollectionReference now extends Query, allowing for fluent and intuitive database querying.

0.1.0

BREAKING CHANGE: Updated the HappyPlatform.initialize() method. It now accepts a Map<String, String> of projects to support multiple API keys, making the SDK more flexible and scalable.

HappyPlatform.firestore() now accepts an optional projectName to switch between initialized projects.

Simplified the internal Dio instance management for better multi-project support.

0.0.1

Initial release of the Happy Platform SDK.

Supports basic CRUD operations (Create, Read, Update, Delete).

Provides a simple, fluent API for interacting with your Happy Platform backend.

