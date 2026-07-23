# Asterion Scraper - Web Novel Scraper

## Overview

This project contains a web scraper built with Node.js and TypeScript designed to extract chapter content from novel websites. It currently targets a predefined list of novels hosted on `novelfire.net`.

The scraper performs the following steps:

1. Fetches basic novel details (title, author, chapters, etc.).
2. Determines the latest chapter number by checking the chapter list page sorted descendingly.
3. Iterates from chapter 1 up to the latest chapter number.
4. For each chapter, it constructs the URL dynamically.
5. Scrapes the chapter title and content using Axios for HTTP requests and Cheerio for HTML parsing.
6. Saves the novel details and all scraped chapter content to a PostgreSQL database.

## Technologies Used

- Node.js
- TypeScript
- Axios (for HTTP requests)
- Cheerio (for HTML parsing)
- pg (for PostgreSQL interaction)
- dotenv (for environment variables)
- ts-node (for running TypeScript directly)
- ESLint (for linting)

## Setup

1. **Prerequisites:** Ensure you have [Node.js](https://nodejs.org/) (which includes npm) and [PostgreSQL](https://www.postgresql.org/download/) installed and running.
2. **Clone the repository:**

    ```bash
    git clone https://github.com/your-username/asterion-scraper.git # Replace with your actual repo URL
    cd asterion-scraper
    ```

3. **Install dependencies:**

    ```bash
    npm install
    ```

4. **Configure Environment:**
   - Create a `.env` file in the project root directory (`asterion-scraper/.env`).
   - Add your PostgreSQL connection string to this file:

     ```bash
     DATABASE_URL=postgresql://username:password@localhost:5432/asterion_scraper
     ```

     (Replace with your actual PostgreSQL connection string.)

## Running the Scraper

Once the environment variables are set and PostgreSQL is running, you can start the scraper:

```bash
npm start
```

Alternatively, if you want to run the TypeScript file directly (ensure dependencies are installed):

```bash
node --loader ts-node/esm scraper.ts
```

The script will start fetching novel details, determine the chapter range, and then begin scraping each chapter sequentially. Progress will be logged to the console. Upon completion, the novel details and chapter content will be saved or updated in your configured PostgreSQL database.

**Note:** The script includes a 1-second delay between chapter requests to avoid overloading the target server. Scraping a large number of chapters will take a significant amount of time.

## Bun REST API

This project now includes a Bun-based REST API for reading and writing novel and chapter data in PostgreSQL.

### Prerequisites

- Bun installed (https://bun.sh/)
- PostgreSQL running
- `.env` file in the project root with:

```bash
DATABASE_URL=postgresql://username:password@localhost:5432/asterion_scraper
PORT=3000
```

`PORT` is optional locally (defaults to `3000`), but recommended for consistency with deployment.

### Start the API

Development:

```bash
npm run api:dev
```

Production-style start (same runtime command, suitable for hosts like Railway):

```bash
npm run api:start
```

### API Conventions

- Base URL: `http://localhost:3000`
- Content type for writes: `application/json`
- Success shape:
  - Single object: `{ "data": { ... } }`
  - List responses: `{ "data": [ ... ], "meta": { ... } }`
- Error shape:
  - `{ "error": "message" }`

### Endpoints

#### Health Check

`GET /health`

Example:

```bash
curl -s http://localhost:3000/health
```

Example response:

```json
{
  "ok": true
}
```

#### List Novels

`GET /novels`

Query params:
- `page` (optional, positive integer, default `1`)
- `pageSize` (optional, positive integer, default `25`, max `100`)
- `limit` (optional, positive integer, default `25`, max `100`)
- `offset` (optional, non-negative integer, default `0`)
- `search` (optional, case-insensitive match on `title` or `author`)

Pagination supports both styles:
- Page-based: `page` + `pageSize`
- Offset-based: `limit` + `offset`

Do not mix the two styles in the same request.

Example:

```bash
curl -s "http://localhost:3000/novels?page=1&pageSize=10&search=shadow"
```

Example response:

```json
{
  "data": [
    {
      "_id": 1,
      "title": "Shadow Slave",
      "novelUrl": "https://novelfire.net/book/shadow-slave",
      "author": "Guiltythree",
      "rank": "1",
      "totalChapters": "2200+",
      "views": "1000000+",
      "bookmarks": "50000+",
      "status": "ONGOING",
      "genres": ["Fantasy", "Action"],
      "summary": "A boy enters a deadly world...",
      "chaptersUrl": "https://novelfire.net/book/shadow-slave/chapters",
      "imageUrl": "https://...",
      "rating": 9.1,
      "lastScraped": "2026-03-02T10:00:00.000Z",
      "createdAt": "2026-03-01T08:00:00.000Z",
      "updatedAt": "2026-03-02T10:00:00.000Z"
    }
  ],
  "meta": {
    "count": 1,
    "total": 1,
    "page": 1,
    "pageSize": 10,
    "totalPages": 1,
    "hasNextPage": false,
    "hasPreviousPage": false,
    "limit": 10,
    "offset": 0
  }
}
```

#### Get Novel by ID

`GET /novels/:id`

Example:

```bash
curl -s http://localhost:3000/novels/1
```

If the novel does not exist, returns `404`:

```json
{
  "error": "Novel with id 1 not found."
}
```

#### Create or Update Novel (Upsert)

`POST /novels`

Required fields:
- `title` (string)
- `novelUrl` (string, used for upsert conflict key)

Optional fields:
- `author`, `rank`, `totalChapters`, `views`, `bookmarks`, `status`, `summary`, `chaptersUrl`, `imageUrl` (string or omitted)
- `genres` (string array)
- `rating` (number `0-10` or `null`)
- `lastScraped` (ISO date string; defaults to current time if omitted)

Example:

```bash
curl -s -X POST http://localhost:3000/novels \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Shadow Slave",
    "novelUrl": "https://novelfire.net/book/shadow-slave",
    "author": "Guiltythree",
    "genres": ["Fantasy", "Action"],
    "rating": 9.1
  }'
```

#### List Chapters for a Novel

`GET /novels/:id/chapters`

Query params:
- `page` (optional, positive integer, default `1`)
- `pageSize` (optional, positive integer, default `25`, max `100`)
- `limit` (optional, positive integer, default `25`, max `100`)
- `offset` (optional, non-negative integer, default `0`)

Pagination supports both styles, but they cannot be mixed in one request.

Example:

```bash
curl -s "http://localhost:3000/novels/1/chapters?page=1&pageSize=20"
```

If novel does not exist, returns `404`.

`GET /novels/:id/chapters` returns lightweight chapter list items (no `content` field) for faster responses. Use `GET /chapters/:id` to fetch full chapter content.

#### Create or Update Chapter (Upsert)

`POST /novels/:id/chapters`

Required fields:
- `chapterNumber` (positive integer; used with `novel_id` for upsert)
- `url` (string)
- `title` (string)
- `content` (string)

Example:

```bash
curl -s -X POST http://localhost:3000/novels/1/chapters \
  -H "Content-Type: application/json" \
  -d '{
    "chapterNumber": 1,
    "url": "https://novelfire.net/book/shadow-slave/chapter-1",
    "title": "Chapter 1",
    "content": "Chapter text..."
  }'
```

If novel does not exist, returns `404`.

#### Get Chapter by ID

`GET /chapters/:id`

Example:

```bash
curl -s http://localhost:3000/chapters/10
```

If chapter does not exist, returns `404`.

### Common Error Codes

- `400` invalid path/query/body input
- `404` resource not found
- `500` unexpected server/database error

### Local API Test Flow

1. Start API with `npm run api:dev`
2. Verify health: `curl -s http://localhost:3000/health`
3. Upsert a novel with `POST /novels`
4. Fetch novels with `GET /novels`
5. Upsert a chapter with `POST /novels/:id/chapters`
6. Fetch chapter list with `GET /novels/:id/chapters`
7. Fetch a single chapter with `GET /chapters/:id`

### Railway Deployment (Bun)

Railway can host Bun apps. Use these defaults:

- Start command: `bun run api.ts` (or `npm run api:start`)
- Ensure env vars are set in Railway:
  - `DATABASE_URL` (PostgreSQL connection string)
  - `PORT` (Railway sets this automatically; your app already reads it)
- Health check endpoint: `/health`

Optional `railway.toml`:

```toml
[build]
builder = "NIXPACKS"

[deploy]
startCommand = "bun run api.ts"
healthcheckPath = "/health"
healthcheckTimeout = 120
restartPolicyType = "ON_FAILURE"
```

## Configuration

- The target novels are defined in the `startUrls` array within the `scraper.ts` file. Modify this array to add or remove novels. Ensure selectors in the `scrapeNovelDetails` and `scrapeChapterContent` functions are compatible with `novelfire.net`'s structure.
- The PostgreSQL connection string is configured via the `DATABASE_URL` variable in the `.env` file.

## Future Improvements

- Save scraped data to a file (e.g., JSON, CSV) in addition to the database.
- Implement command-line arguments for specifying the target URL or chapter range.
- Add more robust error handling and retry logic.
- Integrate a proper logging library.
- Potentially use a browser automation tool like Playwright or Puppeteer if sites require JavaScript execution or have stricter anti-bot measures (though Axios/Cheerio is sufficient for the current target).
