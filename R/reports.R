parse_results <- function(databases, all_results) {
  text_results <- 1:length(databases) %>%
    map(function(x) {
      1:length(all_results[[x]]) %>%
        map(function(y) all_results[[x]][[y]]$results[[1]]$message)
    })

  text_call <- 1:length(databases) %>%
    map(function(x) {
      1:length(all_results[[x]]) %>%
        map(function(y) all_results[[x]][[y]]$results[[1]]$call[[1]])
    })

  new_results <- all_results %>%
    map(as.data.frame)

  new_results <- 1:length(databases) %>%
    map(function(.x) mutate(new_results[[.x]],
        database = databases[.x],
        result = as.character(text_results[[.x]]),
        call = as.character(text_call[[.x]])
      )) %>%
    bind_rows() %>%
    mutate(res = ifelse(failed == 0 & error == FALSE, "Passed", "Failed")) %>%
    arrange(desc(database))
}

html_report <- function(
                        results_variable,
                        filename = "dplyr_test_results.html",
                        title = "dplyr SQL translation tests",
                        show_when_complete = TRUE) {
  html_result <- list(
    tags$h1(title),
    1:nrow(results_variable) %>%
      map(function(x) {
        print_result(results_variable[x, ], x)
      })
  )

  save_html(html_result, filename)

  if (show_when_complete) utils::browseURL(filename)
}

print_result <- function(record, id) {
  list(
    tags$h3(tags$strong(paste0(id, " - ", record$database, " - Test: ", record$test))),
    tags$table(
      tags$tr(
        tags$td(tags$strong("")),
        tags$td(tags$strong("File:")),
        tags$td(record$file),
        tags$td(tags$strong("Result:"),
          if (record$failed == 0) {
            paste0("Passed", if (record$error) " had error(s)")
          } else {
            "Failed"
          },
          colspan = 2
        ),
        tags$td(tags$strong("Runtime (In Secs.):  "), round(record$real, digits = 2), colspan = 2)
      ),
      tags$tr(tags$td(tags$p(""))),

      tags$tr(
        tags$td(tags$p("")),
        tags$td(tags$strong("Test Message:"), colspan = 5)
      ),
      tags$tr(
        tags$td(tags$p(""), colspan = 2),
        tags$td(record$result, colspan = 4)
      ),
      tags$tr(tags$td(tags$p(""))),

      tags$tr(
        tags$td(tags$p("")),
        tags$td(tags$strong("Call:"), colspan = 5)
      ),
      tags$tr(
        tags$td(tags$p(""), colspan = 2),
        tags$td(record$call, colspan = 4)
      )
    ),
    tags$br(),
    tags$hr(),
    tags$br()
  )
}


coverage <- function(results) {
  coverage <- results %>%
    group_by(database, res) %>%
    tally() %>%
    spread(res, n) %>%
    mutate(coverage = round(Passed / (Passed + Failed), digits = 2))

  coverage
}


#' Plot Tests
#'
#' Plot the output from `test_single_database` or `test_database` as a ggplot2 object
#' for easy visualization of test success or failure across databases.
#'
#' @param results Output from `test_single_database` or `test_database`
#'
#' @return list of ggplot2 objects / graphs
#'
#' @examples
#' con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#' tbl_data <- dplyr::copy_to(con, testdata)
#' res <- test_database(tbl_data, pkg_test("simple-tests.yml"))
#' plot_tests(res)
#' DBI::dbDisconnect(con)
#'
#' @export
plot_tests <- function(results) {
  dataset <- plot_prep_helper(results)

  dataset %>%
    split(.$testfile) %>% # break different files into different plots
    map(~ .x %>%
          ggplot() +
          ggtitle(label = .x$testfile[[1]]) +
          geom_tile(aes(x = filler, y = justverb, fill = result), color = "black") +
          scale_fill_manual(values = c(Passed = "#4dac26"
                                       , Failed = "#d01c8b"
                                       , Skipped = "#f7f7f7")) +
          facet_grid(context ~ connection, scales = "free") +
          labs(x = "", y = "")
          )
}

#' @rdname plot_tests
#' @export
plot_summary <- function(results) {
  dataset <- plot_prep_helper(results)

  agg_dataset <- dataset %>%
    group_by(connection, testfile, result) %>%
    summarize(count = n()) %>%
    ungroup() %>%
    group_by(connection, testfile) %>%
    summarize(
      pass = sum(ifelse(result == "Passed", count, 0))
      ,fail = sum(ifelse(result == "Failed", count, 0))
      ,skip = sum(ifelse(result == "Skipped", count, 0))
      ) %>%
    mutate(
      score = ifelse(pass + fail == 0, 0, (pass - fail) / (pass + fail))
      , label = paste(pass, fail, skip, sep = " / ")
      , filler = ""
      )

  plot <- agg_dataset %>%
    ggplot() +
    ggtitle(label = "Test Summary", subtitle = "PASS / FAIL / SKIP") +
    geom_tile(aes(x = filler, y = testfile, fill = score), color = "black") +
    geom_text(aes(x = filler, y = testfile, label = label)) +
    scale_fill_gradient2(
      low = "#d01c8b"
      , mid = "#f7f7f7"
      , high = "#4dac26"
      , midpoint = 0
      ) +
    facet_grid( ~ connection, scales = "free") +
    labs(x = "", y = "")

  return(plot)
}

plot_prep_helper <- function(results){
  if (is.list(results) & all(as.logical(lapply(results, is_dbtest_results))) ) {
    prep_results <- suppressWarnings(results %>%
                                       map_df(~ as.data.frame(.x)))
  } else if (is_dbtest_results(results)) {
    prep_results <- results %>% as.data.frame()
  } else {
    stop("Invalid input: did not find a `dbtest_results` object or a list of `dbtest_results` objects")
  }
  dataset <- prep_results %>%
    mutate(
      result = case_when(
        results.skipped ~ "Skipped"
        , results.failed == 1 | results.error ~ "Failed"
        , TRUE ~ "Passed"
      ),
      test = paste0(results.test, "\n", results.context),
      filler = "",
      justverb = sub("\\:\\ .*$", "", x = results.test)
    ) %>%
    select(connection, test, result, filler
           , justverb
           , justtest = results.test, context = results.context
           , testfile = results.file
    )
  return(dataset)
}

#' Print Interactively
#'
#' Prints a list object by executing print on each element.
#' If in an interactive session, prompts to continue after
#' each print.
#'
#' @param .obj The object which needs to be printed interactively
#' @param .interactive Whether to prompt for interactivity
#'
#' @return List of printed objects
#'
#' @rdname print_interactive
#' @export
print_interactive <- function(.obj, .interactive = interactive()){
  UseMethod("print_interactive", .obj)
}

#' @rdname print_interactive
#' @export
print_interactive.list <- function(.obj, .interactive = interactive()){
  returned <- lapply(
    .obj
    , function(x){print_interactive(x, .interactive = .interactive)}
  )
  invisible(returned)
}

#' @rdname print_interactive
#' @export
print_interactive.default <- function(.obj, .interactive = interactive()){
  print(.obj);
  if (.interactive) {
    invisible(readline(prompt="Press [enter] to continue"));
  }
  invisible(.obj)
}


#' Get dbtest Detail
#'
#' Retrieve test details from a list of dbtest_results objects.
#' Returns a much more natural object to work with than nested lists
#' and enables more easily surfacing the _reasons_ that tests
#' failed.
#'
#' @param .obj The dbtest_results object (or a list of such objects) to get detail for
#' @param db optional The database label to filter by
#' @param file optional The test file to filter by
#' @param context optional The test context to filter by
#' @param verb optional The verb to filter by
#'
#' @return A tibble with test details (and stack traces)
#'
#' @export
get_dbtest_detail <- function(.obj, db = NULL, file = NULL, context = NULL, verb = NULL) {

  get_dbs <- lapply(.obj, function(x, db){
    if (x[["connection"]] == db || is.null(db)) {
      return(x)
    } else {
      return(NULL)
    }}, db = db)

  db_names <- as.character(lapply(get_dbs, function(x){x[["connection"]]}))
  detail <- lapply(
    get_dbs
    , function(x, file, context, verb){
      get_testthat_detail(x[["results"]]
                          , file = file
                          , context = context
                          , verb = verb
                          )
    }
    , file = file, context = context, verb = verb
  )

  present_detail <- set_names(detail, db_names)
  pretty_output <- mapply(
   function(x, name){
     x %>%
       tibble::tibble(
         test = names(.)
         , alt = .
       ) %>%
       dplyr::mutate(alt2 = as.character(lapply(alt, function(x){x[[1]][[1]]}))) %>%
       dplyr::select(
         test
         , !!!set_names("alt2", name)
         , !!!set_names("alt",paste0(name,"_raw"))
       )
     }
   , x = present_detail
   , name = as.list(names(present_detail))
   , SIMPLIFY = FALSE
   ) %>%
   purrr::reduce(dplyr::left_join, by = "test")

  return(pretty_output)
}


get_testthat_detail <- function(.obj, file = NULL, context = NULL, verb = NULL) {

  res <- lapply(.obj, filter_testthat_results
         , file = file
         , context = context
         , verb = verb
         )
  res <- res[!as.logical(lapply(res, is.null))]

  res_test <- as.character(lapply(res, function(x){x[["test"]]}))
  res_verb <- sub("\\:\\ .*$", "", x = res_test)
  res_vector <- sub("^.*\\:\\ ", "", x = res_test)

  res_detail <- lapply(res, function(x){x[["results"]]})

  return(
    set_names(res_detail, res_test)
    )
}


filter_testthat_results <- function(.obj, file = NULL, context = NULL, verb = NULL) {
  if (
    (.obj[["file"]] == file || is.null(file)) &&
    (.obj[["context"]] == context || is.null(context)) &&
    (sub("\\:\\ .*$", "", x = .obj[["test"]]) == verb || is.null(verb))
  ) {
    return(.obj)
  } else {
    return(NULL)
  }
}
