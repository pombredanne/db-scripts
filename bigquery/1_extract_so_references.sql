--- Status: 15.02.2018
--- Execute this in BigQuery

--- select all source code lines of text files that contain a link to Stack Overflow
SELECT
  file_id,
  size,
  copies,
  REGEXP_REPLACE(
      REGEXP_EXTRACT(LOWER(line), r'(https?://stackoverflow\.com/[^\s)\.\"]*)'),
      r'(^https)',
      'http'
  ) as url,
  line
FROM (
  SELECT
    file_id,
    size,
    copies,
    line
  FROM (
    SELECT
      id as file_id,
      size,
      copies,
      SPLIT(content, '\n') as lines
    FROM `bigquery-public-data.github_repos.contents`
    WHERE
      binary = false
      AND content is not null
  )
  CROSS JOIN UNNEST(lines) as line  
)
WHERE REGEXP_CONTAINS(line, r'(?i:https?://stackoverflow\.com/[^\s)\.\"]*)');

=> so_references_2018_02_15.matched_lines


--- join with table "files" to get information about repos
SELECT
  lines.file_id as file_id,
  repo_name,
  REGEXP_EXTRACT(ref, r'refs/heads/(.+)') as branch,
  path,
  size,
  copies,
  url,
  line
FROM `soposthistory.so_references_2018_02_15.matched_lines` as lines
LEFT JOIN `bigquery-public-data.github_repos.files` as files
ON lines.file_id = files.id;

=> so_references_2018_02_15.matched_files


--- normalize the SO links to (http://stackoverflow.com/(a/q)/<id>)
SELECT
  file_id,
  repo_name,
  branch,
  path,
  size,
  copies,
  CASE
    --- DO NOT replace the distinction between answers and questions, because otherwise URLs like this won't be matched: http://stackoverflow.com/a/3758880/1035417
    WHEN REGEXP_CONTAINS(LOWER(url), r'(https?:\/\/stackoverflow\.com\/a\/[\d]+)')
    THEN CONCAT("http://stackoverflow.com/a/", REGEXP_EXTRACT(LOWER(url), r'https?:\/\/stackoverflow\.com\/a\/([\d]+)'))
    WHEN REGEXP_CONTAINS(LOWER(url), r'(https?:\/\/stackoverflow\.com\/q\/[\d]+)')
    THEN CONCAT("http://stackoverflow.com/q/", REGEXP_EXTRACT(LOWER(url), r'https?:\/\/stackoverflow\.com\/q\/([\d]+)'))
    WHEN REGEXP_CONTAINS(LOWER(url), r'https?:\/\/stackoverflow\.com\/questions\/[\d]+\/[^\s\/\#]+(?:\/|\#)([\d]+)')
    THEN CONCAT("http://stackoverflow.com/a/", REGEXP_EXTRACT(LOWER(url), r'https?:\/\/stackoverflow\.com\/questions\/[\d]+\/[^\s\/\#]+(?:\/|\#)([\d]+)'))
    WHEN REGEXP_CONTAINS(LOWER(url), r'(https?:\/\/stackoverflow\.com\/questions\/[\d]+)')
    THEN CONCAT("http://stackoverflow.com/q/", REGEXP_EXTRACT(LOWER(url), r'https?:\/\/stackoverflow\.com\/questions\/([\d]+)'))
    ELSE url
  END as url,
  line
FROM `soposthistory.so_references_2018_02_15.matched_files`;

=> so_references_2018_02_15.matched_files_normalized


--- extract post id from links, set post type id, and extract file extension from path
SELECT
  file_id,
  repo_name,
  branch,
  path,
  LOWER(REGEXP_EXTRACT(path, r'(\.[^.]+$)')) as file_ext,
  size,
  copies,
  CAST(REGEXP_EXTRACT(url, r'http:\/\/stackoverflow\.com\/(?:a|q)\/([\d]+)') AS INT64) as post_id,
  CASE
    WHEN REGEXP_CONTAINS(url, r'(http:\/\/stackoverflow\.com\/q\/[\d]+)')
    THEN 1
    WHEN REGEXP_CONTAINS(url, r'(http:\/\/stackoverflow\.com\/a\/[\d]+)')
    THEN 2
    ELSE NULL
  END as post_type_id,
  url,
  line
FROM `soposthistory.so_references_2018_02_15.matched_files_normalized`
WHERE
  REGEXP_CONTAINS(url, r'(http:\/\/stackoverflow\.com\/(?:a|q)\/[\d]+)');
  
=> so_references_2018_02_15.matched_files_aq


--- use camel case for column names and remove line content for export to MySQL database
SELECT
  file_id as FileId,
  repo_name as RepoName,
  branch as Branch,
  path as Path,
  file_ext as FileExt,
  size as Size,
  copies as Copies,
  post_id as PostId,
  post_type_id as PostTypeId,
  url as Url
FROM `soposthistory.so_references_2018_02_15.matched_files_aq`;

=> so_references_2018_02_15.PostReferenceGH


--- retrieve info about referenced SO answers
WITH
  answers AS (
    SELECT
      FileId,
      RepoName,
      Branch,
      Path,
      FileExt,
      Size,
      Copies,
      Url,
      PostId,
      PostTypeId,
      comment_count As CommentCount,
      score as Score,
      parent_id as ParentId
    FROM `soposthistory.so_references_2018_02_15.PostReferenceGH` ref
    LEFT JOIN `bigquery-public-data.stackoverflow.posts_answers` a
    ON ref.PostId = a.id
    WHERE PostTypeId=2
  )
SELECT 
  FileId,
  RepoName,
  Branch,
  Path,
  FileExt,
  Size,
  Copies,
  Url,
  PostId,
  PostTypeId,
  CommentCount,
  answers.Score as Score,
  ParentId,
  view_count as ParentViewCount
FROM answers
LEFT JOIN `bigquery-public-data.stackoverflow.posts_questions` q
ON answers.ParentId = q.id;

=> so_references_2018_02_15.PostReferenceGH_Answers


SELECT
  FileId,
  FileExt,
  PostId,
  PostTypeId,
  CommentCount,
  Score,
  ParentViewCount
FROM `soposthistory.so_references_2018_02_15.PostReferenceGH_Answers`;

=> so_references_2018_02_15.PostReferenceGH_Answers_R


--- retrieve info about referenced SO questions
SELECT
  FileId,
  RepoName,
  Branch,
  Path,
  FileExt,
  Size,
  Copies,
  Url,
  PostId,
  PostTypeId,
  comment_count As CommentCount,
  score as Score,
  view_count as ViewCount
FROM `soposthistory.so_references_2018_02_15.PostReferenceGH` ref
LEFT JOIN `bigquery-public-data.stackoverflow.posts_questions` q
ON ref.PostId = q.id
WHERE PostTypeId=1;

=> so_references_2018_02_15.PostReferenceGH_Questions


SELECT
  FileId,
  FileExt,
  PostId,
  PostTypeId,
  CommentCount,
  Score,
  ViewCount
FROM `soposthistory.so_references_2018_02_15.PostReferenceGH_Questions`;

=> so_references_2018_02_15.PostReferenceGH_Questions_R
