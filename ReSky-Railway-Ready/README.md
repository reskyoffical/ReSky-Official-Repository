# Skype Revival Online Backend (experimental)

This package is a deployable, internet-facing compatibility backend for the Skype revival project. It provides HTTPS REST APIs, WebSocket presence/messaging, accounts, contacts and message history.

## Important
This does **not** claim to be an official Microsoft Skype server, and it does not impersonate Microsoft's service. The original Skype 8.150 Windows client will not automatically connect to this server simply because it is online. A compatibility/redirect layer for that exact client still has to be identified and tested.

## Deploy
### Render
1. Create a new Web Service from this folder/repository.
2. Select Docker.
3. Render will use `render.yaml` if the repository is connected as a Blueprint.
4. The service exposes `/health` and `/docs`.

### Railway
Deploy the folder as a Docker service. Railway supplies `PORT` automatically.

## Local
Docker:
`docker build -t skype-revival .`
`docker run --rm -p 8080:8080 -e JWT_SECRET="replace-this" -v skype-data:/app/data skype-revival`

Then open `http://localhost:8080/docs`.

## API
POST `/api/v1/register`
POST `/api/v1/login`
GET `/api/v1/me`
GET `/api/v1/users?q=name`
POST `/api/v1/contacts`
GET `/api/v1/contacts`
POST `/api/v1/messages`
GET `/api/v1/messages/{username}`
WebSocket `/ws?token=...`

## Next compatibility milestone
Capture the network requests from the exact Skype 8.150.0.125 client in an isolated Windows test environment, then implement only the required compatibility endpoints/redirect behavior. The backend above is intentionally separate from Microsoft infrastructure.
