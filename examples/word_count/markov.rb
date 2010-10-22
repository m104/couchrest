#!/usr/bin/env ruby

require 'timeout'

$:.unshift File.join(File.dirname(__FILE__), '..', '..','lib')
require 'couchrest'

cr = CouchRest.new("http://127.0.0.1:5984")
db = cr.database('word-count-example')

# this script assumes that the word_count_insert.rb script
# has been run successfully
unless db
  puts "To create the 'word-count-example' database, please run:"
  puts "  ruby word_count_insert.rb"
  puts "Then come back and run this script again!"
  puts "Go on, we'll be patient..."
  exit -1
end

chain_reduce = 

begin 
  db.get("_design/markov")
rescue RestClient::ResourceNotFound => e
  db.save_doc({
    "_id" => "_design/markov",
    :views => {
      'chain-reduce' => {
        :map => 'function(doc) {
            var words = doc.text.split(/[^a-z\'.,]+/i).filter(function(w) {
              return w.length > 0;
            });

            for (var i = 0, l = words.length; i < l; i++) {
              chain = words.slice(i, i + 4);
              if (chain.length > 2) {
                emit(chain, doc.title);
              }
            }
          }',

        :reduce => 'function(key,vs,c) {
            if (c) {
              return sum(vs);
            } else {
              return vs.length;
            }
          }'
      }
    }
  })
end

begin
  timeout(5) do
    # try a random word, just to check on the view
    db.view('markov/chain-reduce',
            :startkey => ['zzyz',nil],
            :endkey => ['zzyz',{}],
            :stale => 'ok')
  end
rescue Timeout::Error
  # nothing
end

if task = cr.active_tasks.select{|t| t['task'] == 'word-count-example _design/markov'}.first
  print <<-eos
NOTE: The view is not quite ready, so you can either cancel this script
      and come back later or wait for the documents to be fully indexed.
      You can still query the view with "stale=ok", but you won't get
      up-to-date answers...
eos
end

while task
  # the background view indexer is working away...
  print "\rView status: " + task['status']
  sleep 2
  task = cr.active_tasks.select{|t| t['task'] == 'word-count-example _design/markov'}.first
  puts "" unless task
end

puts "Welcome to the Classics Sentence Finisher!"
puts "Start a sentence, hit ENTER, and watch this script try to finish it"
puts "with words from the masters."
puts ""

print ": "

while sentence = STDIN.gets
  words = sentence.strip.split(/\s+/)
  break if words.empty?

  print "> " + words.join(' ') + ' '

  last_word = ''
  word = words.last

  while word and (word != last_word) and (word !~ /[.!?]$/)
    print word + ' ' unless last_word == ''
    
    last_word = word

    # one or two-word chain basis
    tail = [words.last]
    tail.unshift(words[-2]) if words.size > 1
    tail.unshift(words[-3]) if words.size > 2

    params = {
      :startkey => tail + [nil],
      :endkey => tail + [{}],
      :group_level => tail.size + 1
    }

    results = db.view('markov/chain-reduce', params)

    rows = results['rows'].select{|r|(r['key'][1]!='')}.sort_by{|r|r['value']}
    row = rows[(-1*[rows.length,5].min)..-1].sort_by{rand}[0]
    word = row ? row['key'][tail.size] : nil

    words << word
  end
  
  puts ""
  puts ""
  puts "That was great!  Have another go?"
  puts ""
  print ": "
  
end

puts ""
puts "OK, we're done!"
puts ""
exit


