package com.cloudwick.sync.jobs.fetcher

/**
 * Messages used between akka actors
 * @author ashrith
 */
object Messages {
  /**
   * Message's used by Master
   */
  case class Start()
  case class Counter()
  case class DuplicateCounter()
  case class RepeatedCounter()
  case class InsertedCounter()
  case class SkippedCounter()
  case class FailedCounter()
  case class Stop()
  case class JobsProcessed(
    jobsProcessed: Int,
    jobsFiltered: Int,
    jobsInserted: Int
  )

  /**
   * Message's used by ProcessResponse actor
   */
  case class ProcessPageRequest()
  case class JobUrlProcessed()
  case class JobUrlRepeated()
  case class JobUrlDuplicate()
  case class JobUrlInserted()
  case class JobUrlSkipped()
  case class JobUrlFailed()

  /**
   * Message's used by [] actor
   */
  case class ProcessJobUrl()
  case class JobProcessed()
  case class Job(url: String,
    title: String,
    company: String,
    location: String,
    datePosted: String,
    searchTerm: String,
    grepWord: String
  )
}
