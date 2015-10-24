package com.cloudwick.sync.jobs.fetcher

import akka.actor.{Props, Actor}
import akka.event.Logging
import com.mongodb.casbah.MongoCollection
import play.api.libs.json._
import play.api.libs.functional.syntax._

import scalaj.http.{Http, HttpResponse}

/**
 * Actor to process the whole base uri from the dice api url (alias: m[0-n]; m -> master)
 *
 * This class parses the main url and then sends out each job url to be processed by individual
 * actor ProcessJobPosting.
 *
 * @param baseUrl url of the api entry
 * @param searchTerm keywords to search for (e.g. scala, spark, java, ...)
 * @param age specifies the age of postings to process (number of days old)
 * @param pageNum specifies the page number of process th jobs in
 * @param sort specifies whether to sort the result set
 * @param grep whether to search in the job postings for a specified string (e.g. CON_HIRE)
 * @param collection mongo collection reference to which the documents have to be persisted
 * @author ashrith
 */
class ProcessBase(baseUrl: String,
                  searchTerm: String,
                  age: Int,
                  pageNum: Int,
                  sort: Int,
                  grep: String,
                  collection: MongoCollection) extends Actor {
  val log = Logging(context.system, this)

  override def preStart() = {
    log.debug("Starting ProcessBase")
  }

  override def preRestart(reason: Throwable, message: Option[Any]): Unit = {
    log.error(reason, "Restarting due to [{}] when processing [{}] (baseUrl: [{}]; pageNum: [{}])",
      reason.getMessage, message.getOrElse(""), baseUrl, pageNum)
  }

  def receive = {
    case Messages.ProcessPageRequest =>
      // initialize the http request
      val response: HttpResponse[String] = Http(baseUrl)
        .option(_.setInstanceFollowRedirects(true))
        .param("text", searchTerm)
        .param("age", age.toString)
        .param("page", pageNum.toString)
        .param("sort", sort.toString)
        .param("sd", "d") // descending sort (latest posted jobs first)
        .asString

      val responseBody: JsValue = Json.parse(response.body)

      implicit val resultReader: Reads[(String, String, String, String, String)] = (
        (__ \ "detailUrl").read[String] and
          (__ \ "jobTitle").read[String] and
          (__ \ "company").read[String] and
          (__ \ "location").read[String] and
          (__ \ "date").read[String]
        ).tupled

      (responseBody \ "resultItemList").asOpt[JsArray] match {
        case Some(resultItemList) =>
          val results = (responseBody \ "resultItemList")
            .as[List[(String, String, String, String, String)]]
          for(i <- 0 until results.length) {
            val jobPosting = results(i)
            context.actorOf(
              Props(classOf[ProcessJobPosting], jobPosting._1, i, collection), name=s"pr$i"
            ) ! Messages.Job(
              jobPosting._1,
              jobPosting._2,
              jobPosting._3,
              jobPosting._4,
              jobPosting._5,
              searchTerm,
              grep)
          }
        case None =>
          log.info("No jobs found in this parent url [" + baseUrl + "?text=" + searchTerm + "&age="
            + age.toString + "&page=" + pageNum.toString + "&sort=" + sort.toString + "&sd=d]")
      }
    case Messages.JobUrlDuplicate =>
      context.actorSelection(s"/user/${searchTerm}jobs") ! Messages.DuplicateCounter
    case Messages.JobUrlRepeated =>
      context.actorSelection(s"/user/${searchTerm}jobs") ! Messages.RepeatedCounter
    case Messages.JobUrlInserted =>
      context.actorSelection(s"/user/${searchTerm}jobs") ! Messages.InsertedCounter
    case Messages.JobUrlSkipped =>
      context.actorSelection(s"/user/${searchTerm}jobs") ! Messages.SkippedCounter
    case Messages.JobUrlFailed =>
      context.actorSelection(s"/user/${searchTerm}jobs") ! Messages.FailedCounter
    case x =>
      log.warning("Message not recognized: [{}]", x)
  }
}