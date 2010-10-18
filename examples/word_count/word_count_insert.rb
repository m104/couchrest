#!/usr/bin/env ruby

# ensure that we're loading *this* version of couchrest, wherever we are
LIB_PATH = File.dirname('../../lib/couchrest')
$:.unshift LIB_PATH unless
 $:.include?(LIB_PATH) or
 $:.include?(File.expand_path(LIB_PATH))
 
require 'couchrest'

puts "Connecting to CouchDB..."
couch = CouchRest.new("http://127.0.0.1:5984")

puts "Creating the word-count-example database..."
db = couch.database('word-count-example')
db.delete! rescue nil
db = couch.create_db('word-count-example')

# Create the design doc (view), then insert the documents.
#
# Doing it the other way around leaves the 'word_count' view
# inaccessible, even with "stale => ok", until the entire
# corpus has been indexed.

word_count = {
  :map => 'function(doc){
    var words = doc.text.split(/\W/);
    words.forEach(function(word){
      if (word.length > 0) emit([word,doc.title],1);
    });
  }',
  :reduce => 'function(key,combine){
    return sum(combine);
  }'
}

puts "Creating the 'word_count' view..."

db.delete_doc(db.get("_design/word_count")) rescue RestClient::ResourceNotFound

db.save_doc({
  "_id" => "_design/word_count",
  :views => {
    :words => word_count
  }
})

puts "Preparing the source material..."
puts "(each line of each book forms its own document in the database)"

books = {
  'outline-of-science.txt' => 'http://www.gutenberg.org/files/20417/20417.txt',
  'ulysses.txt' => 'http://www.gutenberg.org/files/4300/4300.txt',
  'america.txt' => 'http://www.gutenberg.org/files/16960/16960.txt',
  'da-vinci.txt' => 'http://www.gutenberg.org/dirs/etext04/7ldv110.txt'
}

books.each do |file, url|
  path = File.join(File.dirname(__FILE__),file)
  unless File.exists?(path)
    puts "Downloading #{file} ..."
    `curl -s #{url} > #{path}`
  end
  title = file.split('.')[0]
  File.open(File.join(File.dirname(__FILE__),file),'r') do |file|
    lines = []
    chunk = 1
    while line = file.gets
      lines << line
      if lines.length > 10
        db.save_doc({
          :title => title,
          :chunk => chunk, 
          :text => lines.join('')
        })
        chunk += 1
        print "\rInserting lines from #{title}.txt: line #{chunk}"
        lines = []
      end
    end
  end
  puts "\n"
end

puts "Done!  The 'word-count-example' database should now be stuffed with words to count."

