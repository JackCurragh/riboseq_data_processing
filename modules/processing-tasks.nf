


process rRNA_MAPPING {

	publishDir "$params.study_dir/less_rRNA_fastq_files", mode: 'copy', pattern: '*_less_rRNA.fastq'
	publishDir "$params.study_dir/rRNA_alignment_stats", mode: 'copy', pattern: '*_rRNA_stats.txt'

	input: 
	file clipped_fastq /// from clipped_fastq_channel ///

	output:
	path "${clipped_fastq.baseName}_rRNA_stats.txt" , emit: rRNA_stats
	path "${clipped_fastq.baseName}_less_rRNA.fastq", emit: fastq_less_rRNA

	"""
	bowtie -p 8 -v 3 --norc --phred33-qual $params.rRNA_index -q ${clipped_fastq} --un ${clipped_fastq.baseName}_less_rRNA.fastq 2> ${clipped_fastq.baseName}_rRNA_stats.txt 
	"""
}

/* ORIGINALLY THE BELOW PROCESS WAS NAMED "fastqc_on_raw". It has been updated for consistency, considering we are
using fastqc on processed reads in this new version (sequences with no adapters and no rRNAs)-> new name is fastqc_on_processed */

process FASTQC_ON_PROCESSED {

	publishDir "$params.study_dir/fastqc", mode: 'copy'
	
	input:
	file processed_fastq 

	output:
	path "*_fastqc.{zip,html}", emit: fastqc_full_reports/// into raw_fastqc_dir ///
    path "${processed_fastq.baseName}_fastqc/fastqc_data.txt", emit: fastqc_data

	"""
	fastqc -q $processed_fastq 
    unzip ${processed_fastq.baseName}_fastqc.zip
	"""
}

process MULTIQC_ON_FASTQ {

	publishDir "$params.study_dir/multiqc", mode: 'copy'

	input:
	file ('fastqc/*')

	output:
	file "multiqc_report.html"
	
	"""
	multiqc $params.study_dir/fastqc
	"""
}


/* -------------------------
TRANSCRIPTOME MAPPING BRANCH
---------------------------- */


process TRANSCRIPTOME_MAPPING {

	publishDir "$params.study_dir/trips_alignment_stats", mode: 'copy', pattern: '*_trips_alignment_stats.txt' 

	input:    
	file less_rrna_fastq /// from fastq_less_rRNA ///

	output:
	path "${less_rrna_fastq.baseName}_transcriptome.sam", emit: transcriptome_sam
	path "${less_rrna_fastq.baseName}_trips_alignment_stats.txt", emit: mRNA_alignment_stats

	"""
	bowtie -p 8 --norc -a -m 100 -l 25 -n 2 $params.transcriptome_index -q ${less_rrna_fastq} -S ${less_rrna_fastq.baseName}_transcriptome.sam  > ${less_rrna_fastq.baseName}_trips_alignment_stats.txt 2>&1
	"""
} 

process TRANSCRIPTOME_SAM_TO_BAM {

	input:
	file transcriptome_sam /// from transcriptome_sams ///

	output:
	file "${transcriptome_sam.baseName}.bam_sorted" /// into sorted_bams ///

	"""
	samtools view -@ 8 -b -S ${transcriptome_sam.baseName}.sam -o ${transcriptome_sam.baseName}.bam
	samtools sort -m 1G -n -@ 8 ${transcriptome_sam.baseName}.bam > ${transcriptome_sam.baseName}.bam_sorted
	"""
}

process BAM_TO_SQLITE {

	publishDir "$params.study_dir/sqlites", mode: 'copy', pattern: '*.sqlite'

	input:
	file sorted_bam /// from sorted_bams ///

	output:
	file "*.sqlite" /// into sqlite_ch ///

	"""
	python3 $projectDir/scripts/bam_to_sqlite.py --bam ${sorted_bam} --annotation $params.annotation_sqlite --output ${sorted_bam.baseName}.sqlite
	"""
}

process RIBO_QC {

	publishDir "$params.study_dir/riboqc_reports", mode: 'copy', pattern: '*.txt'

	input:
	file sqlite_readfile 
    file fastqc_report

	output:
	file "*.txt" /// into sqlite_ch ///

	"""
	python3 $projectDir/scripts/write_qc_report.py -s ${sqlite_readfile} -r ${fastqc_report} -p $params.annotation_sqlite -o ${sqlite_readfile.simpleName}_riboqc.txt
	"""
}

/* --------------------
GENOME MAPPING BRANCH 
----------------------*/

process GENOME_MAPPING {

	publishDir "$params.study_dir/gwips_alignment_stats", mode: 'copy', pattern: '*_gwips_alignment_stats.txt'
	
    input:
   	file less_rrna_fastq /// from fastq_less_rRNA ///

    output:
    path "${less_rrna_fastq.baseName}_genome.bam_sorted", emit: genome_sorted_bam /// into genome_sams ///
    path "${less_rrna_fastq.baseName}_gwips_alignment_stats.txt", emit: gwips_alignment_stats  /// into gwips_alignment_stats ///

    """
	bowtie -p 8 -m 1 -n 2 --seedlen 25 ${params.genome_index} -q ${less_rrna_fastq} -S 2>> ${less_rrna_fastq.baseName}_gwips_alignment_stats.txt | 

	samtools view -@ 8 -b -S |

	samtools sort -m 1G -@ 8 -o ${less_rrna_fastq.baseName}_genome.bam_sorted
	"""
}



process INDEX_BAM {

	input:
	file genome_sorted_bam

	output:
	path "${genome_sorted_bam.baseName}.bam_sorted", emit: genome_index_sorted_bam ///not outputting the index///
	path "${genome_sorted_bam.baseName}.bam_sorted.bai", emit: genome_index_sorted_bam_bai
	

	"""
	samtools index ${genome_sorted_bam.baseName}.bam_sorted
	"""

}


process BAM_TO_COVBED {

	input:
	file genome_sorted_bam /// genome_aligned_and_sorted_bam ///

	output:
	path "${genome_sorted_bam.baseName}.sorted.cov", emit: coverage_beds

	"""
	bedtools genomecov -ibam ${genome_sorted_bam.baseName}.bam_sorted -g $params.chrom_sizes_file -bg > ${genome_sorted_bam.baseName}.cov
	sort -k1,1 -k2,2n ${genome_sorted_bam.baseName}.cov > ${genome_sorted_bam.baseName}.sorted.cov
	"""
}


process GENOME_BAM_TO_BED {

    input:
	file genome_index_sorted_bam /// from genome_bams ///
	file genome_index_sorted_bam_bai

    output:
	path "${genome_index_sorted_bam.baseName}.bam_sorted.sorted.bed", emit: sorted_beds /// into sorted_beds ///
    	
    """
	python3 $projectDir/scripts/bam_to_bed.py ${genome_index_sorted_bam.baseName}.bam_sorted 15  $params.genome_fasta
	sort -k1,1 -k2,2n ${genome_index_sorted_bam.baseName}.bam_sorted.bed > ${genome_index_sorted_bam.baseName}.bam_sorted.sorted.bed
	"""
}


process BED_TO_BIGWIG {

	publishDir "$params.study_dir/bigwigs", mode: 'copy', pattern: '*.bw'

	input:
	file bedfile /// from sorted_beds ///
	
    output:
	file "*.bw"  /// into bigwigs ///

	"""
	$projectDir/scripts/bedGraphToBigWig ${bedfile} $params.chrom_sizes_file ${bedfile.baseName}.coverage.bw
	"""
}


process GWIPS_INSERTS {

	publishDir "$params.study_dir/gwips_inserts", mode: 'copy', pattern: '*.txt'

	input:
	file run_metadata
	file study_metadata 
	file annotation_inventory_sqlite

	output:
	file "*.txt" /// into gwips_inserts ///

	"""
	python3 $projectDir/scripts/write_GWIPS_inserts.py -s ${study_metadata} -m ${run_metadata} --db ${annotation_inventory_sqlite} -o ${run_metadata.baseName}_gwips_inserts.txt
	"""
}