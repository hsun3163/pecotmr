% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/twas_weights.R
\name{twas_weights_cv}
\alias{twas_weights_cv}
\title{Cross-Validation for weights selection in Transcriptome-Wide Association Studies (TWAS)}
\usage{
twas_weights_cv(
  X,
  Y,
  fold = NULL,
  sample_partitions = NULL,
  weight_methods = NULL,
  max_num_variants = NULL,
  variants_to_keep = NULL,
  num_threads = 1,
  ...
)
}
\arguments{
\item{X}{A matrix of samples by features, where each row represents a sample and each column a feature.}

\item{Y}{A matrix (or vector, which will be converted to a matrix) of samples by outcomes, where each row corresponds to a sample.}

\item{fold}{An optional integer specifying the number of folds for cross-validation.
If NULL, 'sample_partitions' must be provided.}

\item{sample_partitions}{An optional dataframe with predefined sample partitions,
containing columns 'Sample' (sample names) and 'Fold' (fold number). If NULL, 'fold' must be provided.}

\item{weight_methods}{A list of methods and their specific arguments, formatted as list(method1 = method1_args, method2 = method2_args), or alternatively a character vector of method names (eg, c("susie_weights", "enet_weights")) in which case default arguments will be used for all methods.
methods in the list can be either univariate (applied to each column of Y) or multivariate (applied to the entire Y matrix).}

\item{max_num_variants}{An optional integer to set the randomly selected maximum number of variants to use for CV purpose, to save computing time.}

\item{variants_to_keep}{An optional integer to ensure that the listed variants are kept in the CV when there is a limit on the max_num_variants to use.}

\item{num_threads}{The number of threads to use for parallel processing.
If set to -1, the function uses all available cores.
If set to 0 or 1, no parallel processing is performed.
If set to 2 or more, parallel processing is enabled with that many threads.}
}
\value{
A list with the following components:
\itemize{
  \item `sample_partition`: A dataframe showing the sample partitioning used in the cross-validation.
  \item `prediction`: A list of matrices with predicted Y values for each method and fold.
  \item `metrics`: A matrix with rows representing methods and columns for various metrics:
    \itemize{
      \item `corr`: Pearson's correlation between predicated and observed values.
      \item `adj_rsq`: Adjusted R-squared value (which indicates the proportion of variance explained by the model) that accounts for the number of predictors in the model.
      \item `pval`: P-value assessing the significance of the model's predictions.
      \item `RMSE`: Root Mean Squared Error, a measure of the model's prediction error.
      \item `MAE`: Mean Absolute Error, a measure of the average magnitude of errors in a set of predictions.
    }
  \item `time_elapsed`: The time taken to complete the cross-validation process.
}
}
\description{
Performs cross-validation for TWAS, supporting both univariate and multivariate methods.
It can either create folds for cross-validation or use pre-defined sample partitions.
For multivariate methods, it applies the method to the entire Y matrix for each fold.
}
