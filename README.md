Happy Platform SDK

Happy Platform SDK waa backend fudud oo kuu ogolaanaya inaad ku dhisto barnaamijyadaada si degdeg ah adigoo isticmaalaya:

Platform user authentication (Register/Login)

Project creation & management

Firestore-like document storage API (CRUD)

Features

✅ JWT-based user auth

✅ API Key validation for project access

✅ RESTful CRUD endpoints

✅ Chi router & PostgreSQL support

✅ Modular structure (/internal/api, /internal/storage, etc.)

API Endpoints (Sample)

Auth

POST /api/v1/platform/register

POST /api/v1/platform/login

Projects

GET /api/v1/projects

POST /api/v1/projects

DELETE /api/v1/projects/{projectId}

Firestore-like Document Store

POST /api/v1/firestore/collections/{collectionPath:.*}/documents

GET /api/v1/firestore/collections/{collectionPath:.*}/documents

PUT /api/v1/firestore/collections/{collectionPath:.*}/documents/{documentId}

DELETE /api/v1/firestore/collections/{collectionPath:.*}/documents/{documentId}

Installation

git clone https://github.com/your-org/happy-platform.git
cd happy-platform
go run ./cmd/server

Requirements

Go 1.21+

PostgreSQL

License

MIT (See LICENSE file)

# happy_platform_sdk
