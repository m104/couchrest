#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(__FILE__), '..', '..','lib')

require 'couchrest'

puts "Connecting to CouchDB..."
couch = CouchRest.new("http://127.0.0.1:5984")

puts "Creating the word-count-example database..."
db = couch.database('word-count-example')
db.delete! rescue nil
db = couch.create_db('word-count-example')

puts "Preparing the source material..."
puts "(each paragraph of 4+ lines forms its own document in the database)"

books = {
  'sherlock-holmes.txt' => 'http://www.gutenberg.org/cache/epub/1661/pg1661.txt',
  'pride-and-prejudice.txt' => 'http://www.gutenberg.org/cache/epub/1342/pg1342.txt',
  'huckleberry-finn.txt' => 'http://www.gutenberg.org/cache/epub/76/pg76.txt',
  'tale-of-two-cities.txt' => 'http://www.gutenberg.org/cache/epub/98/pg98.txt'
  #'ulysses.txt' => 'http://www.gutenberg.org/files/4300/4300.txt',
  #'outline-of-science.txt' => 'http://www.gutenberg.org/files/20417/20417.txt',
  #'america.txt' => 'http://www.gutenberg.org/files/16960/16960.txt',
  #'da-vinci.txt' => 'http://www.gutenberg.org/dirs/etext04/7ldv110.txt'
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
      line.strip!
      if line =~ /[a-z'"]/i
        # add lines until we hit a non-text line
        lines << line
        next
      end
      
      if lines.length > 3
        db.save_doc({
          :title => title,
          :chunk => chunk, 
          :text => lines.join(' ')
        })
        chunk += 1
        print "\rInserting documents from #{title}.txt: document #{chunk}"
      end
      
      lines = []
    end
  end
  puts "\n"
end

puts "Done!  The 'word-count-example' database should now be stuffed with words to count."

