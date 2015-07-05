package com.cloudwick.sync.confluence

import play.api.libs.json._
import play.api.libs.functional.syntax._

/**
 * Play JSON Space reader wrapper
 */
case class Space(sId: Int, sKey: String, sName: String, sType: String)

object Space {
  implicit val spaceReader: Reads[Space] = (
    (__ \ "id").read[Int] and
      (__ \ "key").read[String] and
      (__ \ "name").read[String] and
      (__ \ "type").read[String]
    )(Space.apply _)
}


