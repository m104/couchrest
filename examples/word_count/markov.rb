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
              return w.match(/[a-z]+/i);
            });

            for (var i = 0, l = words.length; i < l; i++) {
              chain = words.slice(i, i + 9);
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
puts ""
puts "Start a sentence, hit ENTER, and watch this script try to finish it"
puts "with words and phrases from classic works of literature."

rng = Random.new

while true
  # get the user's sentence-starting phrase
  puts ''
  print ': '
  phrase = STDIN.gets

  queued = (phrase || '').strip.split(/\s+/)
  break if queued.empty?

  print '>'
  words = []

  while word = queued.shift
    print ' ' + word
    words << word
    break if word =~ /[.?!]+$/
    next unless queued.empty?

    # one or two-word chain basis
    tail = []
    tail << words[-2] if words.size > 1
    tail << words.last
    arity = tail.size

    params = {
      :startkey => tail + [nil],
      :endkey => tail + [{}],
      :group_level => rng.rand(7) + arity + 1
    }

    # fetch the view
    results = db.view('markov/chain-reduce', params)

    # select the result set (row)
    rows = results['rows'].select{ |r| r['key'][arity] != '' }

    queued = []
    if rows.size > 0
      index = 0
      index = rng.rand(rows.size - 1) if rows.size > 1
      queued = rows[index]['key'][arity..-1]
    end
  end
  
  print '.' unless words.last =~ /[.?!]+$/
  puts ''
  puts ''
  puts 'That was great!  Have another go?'
end

puts ''
puts "OK, we're done!"
puts ''
exit


