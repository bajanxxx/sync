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
  case class Stop()

  /**
   * Message's used by ProcessResponse actor
   */
  case class ProcessPageRequest()
  case class JobUrlProcessed()

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
