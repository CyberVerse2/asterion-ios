def merge_genres(*genre_lists: list[dict]) -> list[dict]:
    genres_by_title: dict[str, dict] = {}
    for genres in genre_lists:
        for genre in genres:
            slug = str(genre.get("slug", "")).strip()
            title = str(genre.get("title", "")).strip()
            if slug and title:
                genres_by_title[title.lower()] = {"slug": slug, "title": title}

    return sorted(genres_by_title.values(), key=lambda genre: genre["title"].lower())
