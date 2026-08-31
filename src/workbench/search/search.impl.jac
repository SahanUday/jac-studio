import from src.workbench.search.search_service { search_in_files }

impl app.handle_query_change(e: any) -> None {
    query = e.target.value;
}

impl app.handle_submit(e: any) -> None {
    e.preventDefault();
    if query.strip() == "" {
        results = [];
        searched = False;
        return;
    }
    searching = True;
    results = await search_in_files(query);
    searching = False;
    searched = True;
}
