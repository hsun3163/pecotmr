#' @export
wald_test_pval <- function(beta, se, n) {
  # Calculate the t statistic
  t_value <- beta / se
  # Degrees of freedom
  df <- n - 2
  # Calculate two-tailed p-value
  p_value <- 2 * pt(-abs(t_value), df = df, lower.tail = TRUE)

  return(p_value)
}

pval_acat <- function(pvals) {
  if (length(pvals) == 1) {
    return(pvals[1])
  }
  stat <- 0.00
  pval_min <- 1.00

  stat <- sum(qcauchy(pvals))
  pval_min <- min(pval_min, min(qcauchy(pvals)))

  return(pcauchy(stat / length(pvals), lower.tail = FALSE))
}

pval_hmp <- function(pvals) {
  # Make sure harmonicmeanp is installed
  if (!requireNamespace("harmonicmeanp", quietly = TRUE)) {
    stop("To use this function, please install harmonicmeanp: https://cran.r-project.org/web/packages/harmonicmeanp/index.html")
  }
  # https://search.r-project.org/CRAN/refmans/harmonicmeanp/html/pLandau.html
  pvalues <- unique(pvals)
  L <- length(pvalues)
  HMP <- L / sum(pvalues^-1)

  LOC_L1 <- 0.874367040387922
  SCALE <- 1.5707963267949

  return(harmonicmeanp::pLandau(1 / HMP, mu = log(L) + LOC_L1, sigma = SCALE, lower.tail = FALSE))
}

pval_global <- function(pvals, comb_method = "HMP", naive = FALSE) {
  # assuming sstats has tissues as columns and rows as pvals
  min_pval <- min(pvals)
  n_total_tests <- pvals %>%
    unique() %>%
    length() # There should be one unique pval per tissue
  global_pval <- if (comb_method == "HMP") pval_hmp(pvals) else pval_acat(pvals) # pval vector
  naive_pval <- min(n_total_tests * min_pval, 1.0)
  return(if (naive) naive_pval else global_pval) # global_pval and naive_pval
}

compute_qvalues <- function(pvalues) {
  # Make sure qvalue is installed
  if (!requireNamespace("qvalue", quietly = TRUE)) {
    stop("To use this function, please install qvalue: https://www.bioconductor.org/packages/release/bioc/html/qvalue.html")
  }
  if (all(is.na(pvalues))) {
    message("All p-values are NA. Returning NA vector.")
    return(rep(NA_real_, length(pvalues)))
  }      
  tryCatch(
    {
      if (length(pvalues) < 2) {
        return(pvalues)
      } else {
        return(qvalue::qvalue(pvalues)$qvalues)
      }
    },
    error = function(e) {
      message("Too few p-values to calculate qvalue, fall back to BH")
      qvalue::qvalue(pvalues, pi0 = 1)$qvalues
    }
  )
}

pval_cauchy <- function(p, na.rm = T) {
  if (na.rm) {
    if (sum(is.na(p))) {
      p <- p[!is.na(p)]
    }
  }
  p[p > 0.99] <- 0.99
  is.small <- (p < 1e-16) & !is.na(p)
  is.regular <- (p >= 1e-16) & !is.na(p)
  temp <- rep(NA, length(p))
  temp[is.small] <- 1 / p[is.small] / pi
  temp[is.regular] <- as.numeric(tan((0.5 - p[is.regular]) * pi))

  cct.stat <- mean(temp, na.rm = T)
  if (is.na(cct.stat)) {
    return(NA)
  }
  if (cct.stat > 1e+15) {
    return((1 / cct.stat) / pi)
  } else {
    return(1 - pcauchy(cct.stat))
  }
}

matxMax <- function(mtx) {
  return(arrayInd(which.max(mtx), dim(mtx)))
}

compute_maf <- function(geno) {
  f <- mean(geno, na.rm = TRUE) / 2
  return(min(f, 1 - f))
}

compute_missing <- function(geno) {
  miss <- sum(is.na(geno)) / length(geno)
  return(miss)
}

compute_non_missing_y <- function(y) {
  nonmiss <- sum(!is.na(y))
  return(nonmiss)
}

compute_all_missing_y <- function(y) {
  allmiss <- all(is.na(y))
  return(allmiss)
}

mean_impute <- function(geno) {
  f <- apply(geno, 2, function(x) mean(x, na.rm = TRUE))
  for (i in 1:length(f)) geno[, i][which(is.na(geno[, i]))] <- f[i]
  return(geno)
}

is_zero_variance <- function(x) {
  if (length(unique(x)) == 1) {
    return(T)
  } else {
    return(F)
  }
}

compute_LD <- function(X) {
  if (is.null(X)) {
    stop("X must be provided.")
  }

  # Mean impute X
  genotype_data_imputed <- apply(X, 2, function(x) {
    pos <- which(is.na(x))
    if (length(pos) != 0) {
      x[pos] <- mean(x, na.rm = TRUE)
    }
    return(x)
  })

  # Check if Rfast package is installed
  if (requireNamespace("Rfast", quietly = TRUE)) {
    # Use Rfast::cora for faster correlation calculation
    R <- Rfast::cora(genotype_data_imputed, large = TRUE)
  } else {
    # Use base R cor function if Rfast is not installed
    R <- cor(genotype_data_imputed)
  }

  colnames(R) <- rownames(R) <- colnames(genotype_data_imputed)
  R
}

#' @importFrom matrixStats colVars
filter_X <- function(X, missing_rate_thresh, maf_thresh, var_thresh = 0, maf = NULL, X_variance = NULL) {
  tol_variants <- ncol(X)
  if (!is.null(missing_rate_thresh) && missing_rate_thresh < 1.0) {
    rm_col <- which(apply(X, 2, compute_missing) > missing_rate_thresh)
    if (length(rm_col)) X <- X[, -rm_col, drop = F]
  }

  # Check if non-NA values are valid genotypes before MAF filtering
  if (!is.null(maf_thresh) && maf_thresh > 0.0) {
    valid_genotypes <- all(sapply(1:ncol(X), function(i) {
      x <- X[!is.na(X[, i]), i]
      all(x %in% c(0, 1, 2))
    }))

    if (valid_genotypes || !is.null(maf)) {
      rm_col <- if (!is.null(maf)) which(maf <= maf_thresh) else which(apply(X, 2, compute_maf) <= maf_thresh)
      if (length(rm_col)) X <- X[, -rm_col, drop = F]
    } else {
      message("Skipping MAF filtering as X does not appear to be 0/1/2 matrix, and no external MAF information is provided")
    }
  }

  rm_col <- which(apply(X, 2, is_zero_variance))
  if (length(rm_col)) X <- X[, -rm_col, drop = F]
  X <- mean_impute(X)
  if (var_thresh > 0) {
    rm_col <- if (!is.null(X_variance)) which(X_variance < var_thresh) else which(colVars(X) < var_thresh)
    if (length(rm_col)) X <- X[, -rm_col, drop = F]
  }
  message(paste0(tol_variants - ncol(X), " out of ", tol_variants, " total variants dropped due to quality control on X matrix."))
  return(X)
}

#' This function performing filters on X variants based on Y subjects for TWAS analysis. This function checks
#' whether the absence (NA) of certain subjects would lead to monomorphic in some variants in X after removing
#' of these subjects data from X.
#' @param missing_rate_thresh Maximum individual missingness cutoff.
#' @param maf_thresh Minimum minor allele frequency (MAF) cutoff.
#' @param var_thresh Minimum variance cutoff for a variant. Default is 0.
#' @param X_variance A vector of variance for X variants.
filter_X_with_Y <- function(X, Y, missing_rate_thresh, maf_thresh, var_thresh = 0, maf = NULL, X_variance = NULL) {
  tol_variants <- ncol(X)
  X <- filter_X(X, missing_rate_thresh, maf_thresh, var_thresh = var_thresh, maf = maf, X_variance = X_variance)
  drop_idx <- do.call(c, lapply(colnames(Y), function(context) {
    subjects_with_na_Y <- rownames(Y)[is.na(Y[, context])]
    X_temp <- X
    X_temp[subjects_with_na_Y, ] <- NA
    rm_col <- which(apply(X_temp, 2, function(x) is_zero_variance(na.omit(x))))
    return(unique(rm_col))
  }))
  drop_idx <- unique(sort(drop_idx))
  if (length(drop_idx)) X <- X[, -drop_idx, drop = FALSE]
  message(paste0("Additional ", length(drop_idx), " variants dropped after considering missing data in Y matrix, with ", ncol(X), " variants left."))
  return(X)
}

filter_Y <- function(Y, n_nonmiss) {
  rm_col <- which(apply(Y, 2, compute_non_missing_y) < n_nonmiss)
  if (length(rm_col)) Y <- Y[, -rm_col]
  rm_rows <- NULL
  if (is.matrix(Y)) {
    rm_rows <- which(apply(Y, 1, compute_all_missing_y))
    if (length(rm_rows)) Y <- Y[-rm_rows, ]
  } else {
    Y <- Y[which(!is.na(Y))]
  }
  return(list(Y = Y, rm_rows = rm_rows))
}


format_variant_id <- function(names_vector) {
  gsub("_", ":", names_vector)
}

#' Converted  Variant ID into a properly structured data frame
#' @param variant_id A data frame or character vector representing variant IDs.
#'   Expected formats are a data frame with columns "chrom", "pos", "A1", "A2",
#'   or a character vector in "chr:pos:A2:A1" or "chr:pos_A2_A1" format.
#' @return A data frame with columns "chrom", "pos", "A1", "A2", where 'chrom'
#'   and 'pos' are integers, and 'A1' and 'A2' are allele identifiers.
#' @noRd
variant_id_to_df <- function(variant_id) {
  # Check if target_variants is already a data.frame with the required columns
  if (is.data.frame(variant_id)) {
    if (!all(c("chrom", "pos", "A1", "A2") %in% names(variant_id))) {
      names(variant_id) <- c("chrom", "pos", "A2", "A1")
    }
    # Ensure that 'chrom' values are integers
    variant_id$chrom <- ifelse(grepl("^chr", variant_id$chrom),
      as.integer(sub("^chr", "", variant_id$chrom)), # Remove 'chr' and convert to integer
      as.integer(variant_id$chrom)
    ) # Convert to integer if not already
    variant_id$pos <- as.integer(variant_id$pos)
    return(variant_id)
  }
  # Function to split a string and create a data.frame
  create_dataframe <- function(string) {
    string <- gsub("_", ":", string)
    parts <- strsplit(string, ":", fixed = TRUE)
    data <- data.frame(do.call(rbind, parts), stringsAsFactors = FALSE)
    colnames(data) <- c("chrom", "pos", "A2", "A1")
    # Ensure that 'chrom' values are integers
    data$chrom <- ifelse(grepl("^chr", data$chrom),
      as.integer(sub("^chr", "", data$chrom)), # Remove 'chr' and convert to integer
      as.integer(data$chrom)
    ) # Convert to integer if not already
    data$pos <- as.integer(data$pos)
    return(data)
  }
  return(create_dataframe(variant_id))
}

#' @importFrom stringr str_split
#' @export
parse_region <- function(region) {
  if (!is.character(region) || length(region) != 1) {
    return(region)
  }

  if (!grepl("^chr[0-9XY]+:[0-9]+-[0-9]+$", region)) {
    stop("Input string format must be 'chr:start-end'.")
  }
  parts <- str_split(region, "[:-]")[[1]]
  df <- data.frame(
    chrom = gsub("^chr", "", parts[1]),
    start = as.integer(parts[2]),
    end = as.integer(parts[3])
  )

  return(df)
}

#' @export
parse_variant_id <- function(region) {
  variants_split <- strsplit(region, ":")
  variants_df <- data.frame(
    chrom = sapply(variants_split, `[`, 1),
    pos = as.integer(sapply(variants_split, `[`, 2)),
    ref = sapply(variants_split, `[`, 3),
    alt = sapply(variants_split, `[`, 4),
    stringsAsFactors = FALSE
  )
  return(variants_df)
}

#' @export
parse_snp_info <- function(snp) {
  parts <- strsplit(snp, ":")[[1]]
  list(
    chr = as.numeric(gsub("chr", "", parts[1])),
    pos = as.numeric(parts[2]),
    ref = parts[3],
    alt = parts[4]
  )
}

# Retrieve a nested element from a list structure
#' @export
get_nested_element <- function(nested_list, name_vector) {
  if (is.null(name_vector)) {
    return(NULL)
  }
  current_element <- nested_list
  for (name in name_vector) {
    if (is.null(current_element[[name]])) {
      stop("Element not found in the list")
    }
    current_element <- current_element[[name]]
  }
  return(current_element)
}



#' Utility function to specify the path to access the target list item in a nested list, especially when some list layers
#' in between are dynamic or uncertain.
#' @export
find_data <- function(x, depth_obj, show_path = FALSE, rm_null = TRUE, rm_dup = FALSE, docall = c, last_obj = NULL) {
  depth <- as.integer(depth_obj[1])
  list_name <- if (length(depth_obj) > 1) depth_obj[2:length(depth_obj)] else NULL
  if (depth == 1 | depth == 0) {
    if (!is.null(list_name)) {
      if (list_name[1] %in% names(x)) {
        if (any(grepl("^[0-9]+$", list_name))) { # list names, indx name, list names
          second_depth <- which(grepl("^[0-9]+$", list_name))[1]
          data <- get_nested_element(x, list_name[1:second_depth[1] - 1])
          remaining_path <- list_name[second_depth:length(list_name)]
          return(find_data(data, remaining_path,
            show_path = show_path,
            rm_null = rm_null, rm_dup = rm_dup, last_obj = names(data)
          ))
        }
        return(get_nested_element(x, list_name))
      }
    } else {
      return(x)
    }
  } else if (is.list(x)) {
    result <- lapply(x, find_data,
      depth_obj = c(depth - 1, list_name), show_path = show_path,
      rm_null = rm_null, rm_dup = rm_dup, last_obj = names(x)
    )
    shared_list_names <- list()
    if (isTRUE(rm_null)) {
      result <- result[!sapply(result, is.null)]
      result <- result[!sapply(result, function(x) length(x) == 0)]
    }
    if (isTRUE(rm_dup)) {
      unique_result <- list()
      unique_counter <- 1
      for (i in seq_along(result)) {
        duplicate_found <- FALSE
        for (j in seq_along(unique_result)) {
          if (identical(result[[i]], unique_result[[j]])) {
            duplicate_found <- TRUE
            shared_list_names[[paste0("unique_list_", j)]] <- c(shared_list_names[[paste0("unique_list_", j)]], names(result)[i])
            break
          }
        }
        if (!duplicate_found) {
          unique_name <- paste0("unique_list_", unique_counter)
          unique_result[[names(result)[i]]] <- result[[i]]
          shared_list_names[[unique_name]] <- names(result)[i]
          unique_counter <- unique_counter + 1
        }
      }
      result <- unique_result
    }

    if (isTRUE(show_path)) {
      if (length(shared_list_names) > 0 & depth == 2) result$shared_list_names <- shared_list_names
      return(result) # Carry original list structure
    } else {
      flat_result <- do.call(docall, unname(result))
      if (length(shared_list_names) > 0 & depth == 2) {
        names(result) <- paste0("unique_list_", 1:length(result))
        result$shared_list_names <- shared_list_names
        return(result)
      } else {
        return(flat_result) # Only return values
      }
    }
  } else {
    message(paste0("list ", depth_obj[length(depth_obj)], " is not found in ", last_obj, ".  \n"))
  }
}

#' Utility function to convert LD region_ids to `region of interest` dataframe
#' @param ld_region_id A string of region in the format of chrom_start_end.
#' @export
region_to_df <- function(ld_region_id, colnames = c("chrom", "start", "end")) {
  region_of_interest <- as.data.frame(do.call(rbind, lapply(strsplit(ld_region_id, "[_:-]"), function(x) as.integer(sub("chr", "", x)))))
  colnames(region_of_interest) <- colnames
  return(region_of_interest)
}

thisFile <- function() {
  cmdArgs <- commandArgs(trailingOnly = FALSE)
  needle <- "--file="
  match <- grep(needle, cmdArgs)
  if (length(match) > 0) {
    ## Rscript
    path <- cmdArgs[match]
    path <- gsub("\\~\\+\\~", " ", path)
    return(normalizePath(sub(needle, "", path)))
  } else {
    ## 'source'd via R console
    return(sys.frames()[[1]]$ofile)
  }
}

load_script <- function() {
  fileName <- thisFile()
  return(ifelse(!is.null(fileName) && file.exists(fileName),
    readChar(fileName, file.info(fileName)$size), ""
  ))
}

#' Find Valid File Path
find_valid_file_path <- function(reference_file_path, target_file_path) {
  # Check if the reference file path exits
  try_reference <- function() {
    if (file.exists(reference_file_path)) {
      return(reference_file_path)
    } else {
      return(NULL)
    }
  }
  # Check if the target file path exists
  try_target <- function() {
    if (file.exists(target_file_path)) {
      return(target_file_path)
    } else {
      # If not, construct a new target path by combining the directory of the reference file path with the target file path
      target_full_path <- file.path(dirname(reference_file_path), target_file_path)
      if (file.exists(target_full_path)) {
        return(target_full_path)
      } else {
        return(NULL)
      }
    }
  }

  target_result <- try_target()
  if (!is.null(target_result)) {
    return(target_result)
  }

  reference_result <- try_reference()
  if (!is.null(reference_result)) {
    return(reference_result)
  }

  stop(sprintf(
    "Both reference and target file paths do not work. Tried paths: '%s' and '%s'",
    reference_file_path, file.path(dirname(reference_file_path), target_file_path)
  ))
}

find_valid_file_paths <- function(reference_file_path, target_file_paths) sapply(target_file_paths, function(x) find_valid_file_path(reference_file_path, x))

#' Filter a vector based on a correlation matrix
#'
#' This function filters a vector `z` based on a correlation matrix `LD` and a correlation threshold `rThreshold`.
#' It keeps only one element among those having an absolute correlation value greater than the threshold.
#'
#' @param z A numeric vector to be filtered.
#' @param LD A square correlation matrix with dimensions equal to the length of `z`.
#' @param rThreshold The correlation threshold for filtering.
#'
#' @return A list containing the following elements:
#'   \describe{
#'     \item{filteredZ}{The filtered vector `z` based on the correlation threshold.}
#'     \item{filteredLD}{The filtered matrix `LD` based on the correlation threshold.}
#'     \item{dupBearer}{A vector indicating the duplicate status of each element in `z`.}
#'     \item{corABS}{A vector storing the absolute correlation values of duplicates.}
#'     \item{sign}{A vector storing the sign of the correlation values (-1 for negative, 1 for positive).}
#'     \item{minValue}{The minimum absolute correlation value encountered.}
#'   }
#'
#' @examples
#' z <- c(1, 2, 3, 4, 5)
#' LD <- matrix(c(
#'   1.0, 0.8, 0.2, 0.1, 0.3,
#'   0.8, 1.0, 0.4, 0.2, 0.5,
#'   0.2, 0.4, 1.0, 0.6, 0.1,
#'   0.1, 0.2, 0.6, 1.0, 0.3,
#'   0.3, 0.5, 0.1, 0.3, 1.0
#' ), nrow = 5, ncol = 5)
#' rThreshold <- 0.5
#'
#' result <- find_duplicate_variants(z, LD, rThreshold)
#' print(result)
#'
#' @export
find_duplicate_variants <- function(z, LD, rThreshold) {
  p <- length(z)
  dupBearer <- rep(-1, p)
  corABS <- rep(0, p)
  sign <- rep(1, p)
  count <- 1
  minValue <- 1

  for (i in 1:(p - 1)) {
    if (dupBearer[i] != -1) next

    idx <- (i + 1):p
    corVec <- abs(LD[i, idx])
    dupIdx <- which(dupBearer[idx] == -1 & corVec > rThreshold)

    if (length(dupIdx) > 0) {
      j <- idx[dupIdx]
      sign[j] <- ifelse(LD[i, j] < 0, -1, sign[j])
      corABS[j] <- corVec[dupIdx]
      dupBearer[j] <- count
    }

    minValue <- min(minValue, min(corVec))
    count <- count + 1
  }

  # Filter z based on dupBearer
  filteredZ <- z[dupBearer == -1]
  filteredLD <- LD[dupBearer == -1, dupBearer == -1, drop = F]

  return(list(filteredZ = filteredZ, filteredLD = filteredLD, dupBearer = dupBearer, corABS = corABS, sign = sign, minValue = minValue))
}

#' Convert Z-scores to Beta and Standard Error
#'
#' This function estimates the effect sizes (beta) and standard errors (SE) from
#' given z-scores, minor allele frequencies (MAF), and a sample size (n) in genetic studies.
#' It supports vector inputs for z-scores and MAFs to process multiple variants simultaneously.
#'
#' @param z Numeric vector. The z-scores of the genetic variants.
#' @param maf Numeric vector. The minor allele frequencies of the genetic variants (0 < maf <= 0.5).
#' @param n Integer. The sample size of the study (assumed to be the same for all variants).
#'
#' @return A data frame containing three columns:
#' \describe{
#'   \item{beta}{The estimated effect sizes.}
#'   \item{se}{The estimated standard errors.}
#'   \item{maf}{The input minor allele frequencies (possibly adjusted if > 0.5).}
#' }
#'
#' @details
#' The function uses the following formulas to estimate beta and SE:
#' Beta = z / sqrt(2p(1-p)(n + z^2))
#' SE = 1 / sqrt(2p(1-p)(n + z^2))
#' Where p is the minor allele frequency.
#'
#' @examples
#' z <- c(2.5, -1.8, 3.2, 0.7)
#' maf <- c(0.3, 0.1, 0.4, 0.05)
#' n <- 10000
#' result <- z_to_beta_se(z, maf, n)
#' print(result)
#' test_data_with_results <- cbind(test_data, results)
#' print(test_data_with_results)
#'
#' @note
#' This function assumes that the input z-scores are normally distributed and
#' that the genetic model is additive. It may not be accurate for rare variants
#' or in cases of imperfect imputation. The function automatically adjusts MAF > 0.5
#' to ensure it's always working with the minor allele.
#' @noRd
z_to_beta_se <- function(z, maf, n) {
  if (length(z) != length(maf)) {
    stop("z and maf must be vectors of the same length")
  }
  # Ensure MAF is the minor allele frequency
  p <- pmin(maf, 1 - maf)
  denominator <- sqrt(2 * p * (1 - p) * (n + z^2))
  beta <- z / denominator
  se <- 1 / denominator
  return(data.frame(beta = beta, se = se, maf = p))
}

#' Filter events based on provided context name pattern
#'       
#' @param events A character vector of event names 
#' @param filters A data frame with character column of type_pattern, valid_pattern, and exclude_pattern. 
#' @param condition Optional label context name 
#' @param remove_all_group Logical if \code{TRUE}, removes all events from the same group and character-defined context.
filter_molecular_events <- function(events, filters, condition = NULL, remove_all_group = FALSE) {
  # filters is a list of filter specifications
  # Each filter spec must have:
  #   type_pattern: pattern to identify event type
  #   And at least ONE of:
  #   valid_pattern: pattern that must exist in group
  #   exclude_pattern: pattern to exclude

  filtered_events <- events
  for (filter in filters) {
    if (is.null(filter$type_pattern) ||
      (is.null(filter$valid_pattern) && is.null(filter$exclude_pattern))) {
      stop("Each filter must specify type_pattern and at least one of valid_pattern or exclude_pattern")
    }
    # Get events of this type
    type_events <- filtered_events[grepl(filter$type_pattern, filtered_events)]
    type_events_all <- type_events
    if (length(type_events) == 0) next
    # Apply valid pattern if specified
    if (!is.null(filter$valid_pattern)) {
      filter$valid_pattern <- strsplit(filter$valid_pattern, ",")[[1]]
      valid_groups <- unique(gsub(
        filter$type_pattern, "\\1",
        type_events[grepl(paste(filter$valid_pattern, collapse = "|"), type_events)]
      ))
      if (length(valid_groups) > 0) {
        type_events <- type_events[grepl(paste(filter$valid_pattern, collapse = "|"), type_events)] # filter for valid pattern in type events
      } else {
        type_events <- character(0)
      }
    }
    # Apply exclusions if specified
    if (!is.null(filter$exclude_pattern)) {
      filter$exclude_pattern <- strsplit(filter$exclude_pattern, ",")[[1]]
      type_events <- type_events[!grepl(paste(filter$exclude_pattern, collapse = "|"), type_events)]
    }
    if (is.null(condition)) condition <- events
    if (length(type_events) == length(events)) {
      message(paste("All events matching", filter$type_pattern, "in", condition, "included in following analysis."))
    } else if (length(type_events) == 0) {
      message(paste("No events matching", filter$type_pattern, "in", condition, "pass the filtering."))
      return(NULL)
    } else {
      exclude_events <- paste0(setdiff(type_events_all, type_events), collapse = ";")
      message(paste("Some events,", exclude_events, "in", condition, "are removed. \n"))
      if (remove_all_group) {
        exclude_events <- setdiff(type_events_all, type_events)
        exclude_groups <- gsub(filter$type_pattern, "\\1", 
                               exclude_events[grepl(paste(filter$exclude_pattern, collapse = "|"), exclude_events)]
        )
        for (i in seq_along(exclude_events)) {
            #if (!any(grepl(exclude_groups[i], type_events))) next  # skip the event if the corresponding group is all removed
            for (x in filter$exclude_pattern) exclude_events[i] <- gsub(x, ".*", exclude_events[i]) # remove exclude pattern from the context
            context_key <- gsub("\\b\\d+\\b", "", exclude_events[i]) # remove stand alone numbers (strings such as "lf2" or "chr8" will be kept)
            # General pattern to match all events of same group ID and similar character structure
            pattern_to_remove <- paste0(".*", exclude_groups[i], ".*")
            # Identify all events that match both the context structure and group ID
            same_group_events <- type_events[grepl(pattern_to_remove, type_events) & grepl(gsub("\\d+", "", context_key), gsub("\\d+", "", type_events))]
            type_events <- setdiff(type_events, same_group_events)
        }
      }
    }
    # Update events list
    filtered_events <- unique(c(
      filtered_events[!grepl(filter$type_pattern, filtered_events)],
      type_events
    ))
  }

  return(filtered_events)
}

