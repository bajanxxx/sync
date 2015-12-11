#
# Monkey Patch Sinatra flash to bootstrap alert
#
module Sinatra
  module Flash
    # Monkey path Style class
    module Style
      def styled_flash(key = :flash)
        return '' if flash(key).empty?
        id = (key == :flash ? 'flash' : "flash_#{key}")
        close = '<a class="close" data-dismiss="alert" href="#">×</a>'
        messages = flash(key).map do |message|
          "  <div class='alert alert-#{message[0]}'>#{close}\n " \
          "#{message[1]}</div>\n"
        end
        "<div id='#{id}'>\n" + messages.join + '</div>'
      end
    end
  end
end
