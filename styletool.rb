require 'tk'
require 'gsl'
#require 'gnuplot'
require 'tkextlib/tile/treeview'

class Document
  attr_reader :name, :author, :wordCount, :countedWords
  def initialize(name, author, text)
    @name = name
    @author = author
    @countedWords = Hash.new(0)
    words = text.downcase.scan(/\w+/)
    if block_given?
      words.each{|word| @countedWords[word] += 1 if yield(word)}
    else
      words.each{|word| @countedWords[word] += 1}
    end
    @wordCount = words.size
  end
  def words
    @countedWords.keys
  end
  def count(word)
    #will return 0 if 'word' not in 'countedWords' since 0 is the default value
    @countedWords[word]
  end
  def relativeFrequency(word)
    @countedWords[word] / @wordCount.to_f
  end
end


class PCAtool
  attr_reader :matrix
  def initialize(vectors)
    @matrix = Matrix.alloc(vectors.flatten, vectors.size, vectors[0].size).transpose
  end
  def center
    avg = Vector.calloc(@matrix.size1) #calloc initalizes all values to 0
    for r in 0..(@matrix.size1 - 1)
      for c in 0..(@matrix.size2 - 1)
        avg[r] += @matrix[r,c] / @matrix.size2.to_f
      end
    end
    avg
  end
  def centeredMatrix
    cm = @matrix.duplicate
    avg = self.center
     for r in 0..(@matrix.size1 - 1)
      for c in 0..(@matrix.size2 - 1)
        cm[r,c] -= avg[r]
      end
    end
    cm
  end
  def scatterMatrix
    cm = self.centeredMatrix
    cm*cm.transpose  
  end
  def reduceDimensions(dims)
    vecs = Array.new(@matrix.size2){Array.new(dims)}
    eigval, eigvec = self.scatterMatrix.eigen_symmv
    cm = self.centeredMatrix
    for c in 0..(@matrix.size2 - 1)
      for e in 0..(dims - 1)
        vecs[c][e] = cm.col(c).row*eigvec.col(e)
      end
    end
    vecs
  end
end

class Interface
  attr_reader :documents
  def initialize
    @documents = Array.new
    @masterWordList = Array.new

    #and now for the GUI
    @root = TkRoot.new() {title 'Style Tool'}

    addfile = proc {
      filename = Tk.getOpenFile
      #if the user clicks "cancel" in the dialog box then filename == ""
      self.addFile(filename) unless filename == ""
    }
    addfolder = proc {
      foldername = Tk.chooseDirectory
      self.addFolder(foldername) unless foldername == ""
    }
    remove = proc {
      self.remove(@tree.focus_item)
    }
    save = proc {
      filename = Tk.getSaveFile("filetypes"=>[["CSV", ".csv"]])
      self.saveToCSV(filename) unless filename == ""
    }
    plotpca = proc {
      c = self.doPCA(2)
      x = c.collect{|coord| coord[0]}
      y = c.collect{|coord| coord[1]}
      graph(Vector.alloc(x),Vector.alloc(y),"-T X -C -m -2 -S 3")
    }
    savepca = proc {
      filename = Tk.getSaveFile("filetypes"=>[["CSV", ".csv"]])
      self.savePCAtoCSV(filename) unless filename == ""
    }
    TkButton.new(@root) {
      text    'Add file'
      command addfile
    }.grid('column'=>0, 'row'=>4,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(@root) {
      text    'Add folder'
      command addfolder
    }.grid('column'=>1, 'row'=>4,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(@root) {
      text    'Remove'
      command remove
    }.grid('column'=>2, 'row'=>4,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(@root) {
      text    'Save as CSV'
      command save
    }.grid('column'=>0, 'row'=>0,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(@root) {
      text    'plot 2D PCA'
      command plotpca
    }.grid('column'=>1, 'row'=>0,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(@root) {
      text    'save 2D PCA'
      command savepca
    }.grid('column'=>2, 'row'=>0,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    wordlisttoggled = proc {
      if @wordListSpecified.get_value == "1"
        filename = Tk.getOpenFile
        unless filename == ""
          self.specifyWordList(filename)
        else #the user hit 'cancel' -- don't change anything!
          @wordListSpecified.set_value("0")
        end
      else
        self.unspecifyWordList
      end
    }
    @wordListSpecified = TkCheckButton.new(@root){
      text "Count specific words only"
      command wordlisttoggled
    }.grid('column'=>1,'row'=> 1, 'sticky'=>'w')

    TkLabel.new{
      @root
      text "Loaded files:"
    }.grid('column'=>0,'row'=>2, 'sticky'=>'w')


    yscroll = proc{|*args| @lbscroll.set(*args)}
    scroll = proc{|*args| @tree.yview(*args)}
    @tree = Tk::Tile::Treeview.new(@root){
      yscrollcommand yscroll
      selectmode 'browse'
    }.grid('column'=>1,'row'=> 2, 'sticky'=>'we')

    @lbscroll = TkScrollbar.new(@root) {
      orient 'vertical'
      command scroll
    }.grid('column'=>2, 'row'=>2,'sticky'=>'wns')

    TkLabel.new{
      @root
      text "Author:"
    }.grid('column'=>0,'row'=>3, 'sticky'=>'w')

    @author = TkVariable.new()
    authorDisp = TkEntry.new(@root) {
      width 30
      relief  'sunken'
    }.grid('column'=>1,'row'=> 3, 'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    authorDisp.textvariable(@author)
    @author.value = 'Unknown'
  end
  def doPCA(dims)
    PCAtool.new(self.coords).reduceDimensions(dims)
  end
  def specifyWordList(filename)
    @wordListSpecified.set_value("1") 
    @masterWordList = IO.read(filename).downcase.scan(/\w+/).uniq
    @documents = Array.new
    @tree.children("").each{|item| @tree.delete(item)}
  end
  def unspecifyWordList
    @wordListSpecified.set_value("0") 
    @documents = Array.new
    @masterWordList = Array.new
    @tree.children("").each{|item| @tree.delete(item)}
  end
  def addFile(filename)
  #add author if need be
  unless @tree.exist?(@author.value)
    @tree.insert('', 'end', :id => @author.value, :text => @author.value)
  end
  @tree.insert( @author.value, 'end', :id => filename, :text => filename)

   if @wordListSpecified.get_value == '1'
      newdoc = Document.new(filename,@author.value,IO.read(filename)) {|word| @masterWordList.include?(word)}
    else
      newdoc = Document.new(filename,@author.value,IO.read(filename))
      @masterWordList = (@masterWordList | newdoc.words).sort
    end
    @documents.push(newdoc)
  end
  def addFolder(path)
    Dir.chdir(path){Dir.foreach(path){|file| self.addFile(file) if File.file?(file)}}
  end
  def remove(item)
    if @documents.collect{|doc| doc.author}.include?(item.id) #have we slected all works by the author?
      @documents.reject!{|doc| doc.author == item.id}
    else #it's a file
      @documents.reject!{|doc| doc.name == item.id}
    end
    unless @wordListSpecified.get_value == '1'
      @masterWordList = @documents.inject([""]){|words,doc| words |doc.words}
    end
    @tree.delete(item)
  end
  def coords
    @documents.collect{|doc| @masterWordList.collect{|word| doc.relativeFrequency(word)}}
  end
  def saveToCSV(filename)
    File.open(filename, "w") do |file|
      #prints the file name at the top of each column
      @documents.each{|doc| file.print(",",doc.author)}
      file.print("\n")
      @documents.each{|doc| file.print(",",doc.name)}
      file.print("\n")
      @masterWordList.each do |word|
        file.print(word)
        @documents.each{|doc| file.print(",",doc.relativeFrequency(word))}
        file.print("\n")
      end
    end
  end
  def savePCAtoCSV(filename,dims=2)
    pca = self.doPCA(dims)
    File.open(filename, "w") do |file|
      #prints the file name at the top of each column
#      @documents.each{|doc| file.print(doc.name,",")}
#      file.print("\n")
#      for i in 0..(dims - 1)
#        pca.each{|coord| file.print(coord[i],",")}
#        file.print("\n")
#      end
pca.each{|arr|
  arr.each{|num| file.print(num," ")}
  file.print("\n")
}
    end    
  end
end


if __FILE__ == $0
  Interface.new
  Tk.mainloop()
end