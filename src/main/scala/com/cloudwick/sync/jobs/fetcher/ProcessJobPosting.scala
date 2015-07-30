package com.cloudwick.sync.jobs.fetcher

import java.io.{InputStreamReader, BufferedReader}
import java.net.{HttpURLConnection, URL}

import akka.actor.Actor
import akka.event.Logging
import com.mongodb.casbah.MongoCollection
import com.mongodb.casbah.commons.MongoDBObject
import com.mongodb.casbah.Imports._
import com.mongodb.casbah.commons.conversions.scala._
import org.joda.time.{DateTimeZone, DateTime}
import org.joda.time.format.DateTimeFormat

import scalaj.http.{Http, HttpOptions, HttpResponse}

/**
 * Actor to process each job url to parse and enrich the posting (alias: pr[0-n] -> processrequest)
 * @param url job url to process
 * @param uid unique id for the actor processing this job url
 * @param collection mongo collection object to insert the processed job's to
 * @author ashrith
 */
class ProcessJobPosting(url: String,
                        uid: Int,
                        collection: MongoCollection) extends Actor {
  val log = Logging(context.system, this)

  val skillsPattern = """\s+<dt.*>Skills:<\/dt>\s+<dd.*>(.*)<\/dd>""".r
  val emailPattern = """\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b""".r
  val phonePattern = """(?:(?:\+?1\s*(?:[.-]\s*)?)?(?:\(\s*([2-9]1[02-9]|[2-9][02-8]1|[2-9][02-8][02-9])\s*\)|([2-9]1[02-9]|[2-9][02-8]1|[2-9][02-8][02-9]))\s*(?:[.-]\s*)?)?([2-9]1[02-9]|[2-9][02-9]1|[2-9][02-9]{2})\s*(?:[.-]\s*)?([0-9]{4})(?:\s*(?:#|x\.?|ext\.?|extension)\s*(\d+))?""".r
  RegisterJodaTimeConversionHelpers()
  val dateFormat = DateTimeFormat.forPattern("yyyy-MM-dd").withZone(DateTimeZone.forID("UTC"))

  override def preStart() = {
    log.debug("Starting ProcessRequest")
  }

  override def preRestart(reason: Throwable, message: Option[Any]): Unit = {
    log.error(reason, "Restarting due to [{}] when processing [{}] (url: {})",
      reason.getMessage, message.getOrElse(""), url)
  }

  def toWords(lines: List[String]) = lines flatMap { line =>
    "[a-zA-Z]+".r findAllIn line map (_.toLowerCase)
  }

  def handleRequest(uRL: String): HttpURLConnection = {
    var conn = new URL(uRL).openConnection().asInstanceOf[HttpURLConnection]
    conn.setReadTimeout(50000)
    conn.setConnectTimeout(10000)

    val status = conn.getResponseCode
    status match {
      case HttpURLConnection.HTTP_OK =>
        conn
      case HttpURLConnection.HTTP_MOVED_TEMP | HttpURLConnection.HTTP_MOVED_PERM |
           HttpURLConnection.HTTP_SEE_OTHER => {
        // handle redirection
        conn = handleRequest(conn.getHeaderField("Location"))
        conn
      }
    }
  }

  def processRequest(uRL: String): String = {
    val conn = handleRequest(uRL)
    val in: BufferedReader = new BufferedReader(new InputStreamReader(conn.getInputStream))
    Stream.continually(in.readLine()).takeWhile(_ != null).mkString("\n")
  }

//  def processRequest(url: String): HttpResponse[String] = {
//    Http(url)
//      .option(_.setInstanceFollowRedirects(true))
//      .option(HttpOptions.connTimeout(10000))
//      .option(HttpOptions.readTimeout(50000))
//      .asString
//  }

  def keepPosting(content: String, searchTerm: String): Boolean = {
    content contains searchTerm
  }

  def getSkills(content: String): List[String] = {
    skillsPattern.findFirstMatchIn(content).map(_ group 1) match {
      case Some(skills) => (skills replaceAll("&nbsp;", "")).split(",").toList
      case None => List()
    }
  }

  def getEmails(content: String): List[String] = {
    emailPattern
      .findAllMatchIn(content)
      .map(s => s.toString())
      .toList
      .filter(!_.equals("email@domain.com"))
      .distinct
  }

  def getPhones(content: String): List[String] = {
    phonePattern
      .findAllMatchIn(content)
      .map(s => s.toString())
      .toList
      .filter(_.length > 10)
      .distinct
  }

  def receive = {
    case Messages.Job(iUrl, title, company, location, date, searchTerm, grepWord) =>
      log.debug("Processing [{}]", iUrl)
      val qDate = DateTime.parse(date, dateFormat)
      try {
        val urlContent = processRequest(iUrl)
        if (keepPosting(urlContent, grepWord)) {
          val skills = getSkills(urlContent)
          val emails = getEmails(urlContent)
          val phoneNums = getPhones(urlContent)

          // splat everything for _keywords
          val keywords = toWords(skills) :::
            toWords(emails) :::
            toWords(List(title)) :::
            toWords(List(company)) :::
            toWords(List(location))

          val sObj = MongoDBObject("url" -> url)

          collection.findOne(sObj) match {
            case Some(obj) =>
              val dObj = sObj ++ ("date_posted" -> qDate)
              collection.findOne(dObj) match {
                // check if the url exists with same date posted then ignore it
                case Some(o) =>
                  log.info("Document with url: [{}] and date: [{}] already exists", url, date)
                case None =>
                  log.info("Repeated job posting fond: [{}]", url)
                  val existingDate = obj("date_posted")
                  val update = MongoDBObject(
                    "$set" -> MongoDBObject("date_posted" -> qDate, "repeated" -> true),
                    "$addToSet" -> MongoDBObject("pdates" -> existingDate)
                  )
                  collection.update(sObj, update)
              }
            case None =>
              // construct a mongo object to insert
              val iObj = MongoDBObject(
                "url" -> iUrl,
                "link_active" -> true,
                "date_posted" -> qDate,
                "search_term" -> searchTerm,
                "source" -> "DICE", // TODO replace this with the parameter
                "title" -> title,
                "company" -> company,
                "location" -> location,
                "skills" -> skills,
                "emails" -> emails,
                "phone_nums" -> phoneNums,
                "read" -> false,
                "hide" -> false,
                "_keywords" -> keywords,
                "version" -> 2
              )
              log.info("Inserting: [{}]", iObj.toString)
              collection.insert(iObj)
          }

          // Update the sender and notify that job url processing completed
          sender() ! Messages.JobUrlProcessed
        } else {
          log.debug("Skipping [{}] as grep_term:'{}' not found", iUrl, grepWord)
          sender() ! Messages.JobUrlProcessed
        }
      } catch {
        case ex: Exception =>
          // exception as the first arg will print the stack trace
          log.error(ex, "Failed parsing url: [{}] because of [{}]", iUrl, ex.getMessage)
          sender() ! Messages.JobUrlProcessed
      }
    case x =>
      log.warning("Message not recognized: [{}]. Path: [{}]", x, sender().path)
  }
}
